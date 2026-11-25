import Foundation
import Security
import CryptoKit

public struct MarketplaceAuthError: LocalizedError {
    public let message: String
    public let requiresSignIn: Bool
    public init(_ message: String, requiresSignIn: Bool = false) { self.message = message; self.requiresSignIn = requiresSignIn }
    public var errorDescription: String? { message }
}
public enum MarketplaceOAuth {
    public static let issuer = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_ew8XPyUxw"
    public static let domain = "https://us-east-1ew8xpyuxw.auth.us-east-1.amazoncognito.com"
    public static let clientID = "bp9irlnljma6v1coebnroo0vo"
    public static let callback = "pocketpad://auth/callback"
    public static let scopes = "openid email pocketpad-api/layouts.write"
    public static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw MarketplaceAuthError("Could not start secure sign-in.") }
        return base64(Data(bytes))
    }
    public static func base64(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    public static func decode64(_ value: String) -> Data? {
        Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - value.count % 4) % 4))
    }
    public static func challenge(_ verifier: String) -> String { base64(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    public static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(fields.sorted { $0.key < $1.key }.map { $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "&").utf8)
    }
    public static func authorizationURL(state: String, nonce: String, verifier: String) -> URL {
        var url = URLComponents(string: domain + "/oauth2/authorize")!
        url.queryItems = ["response_type": "code", "client_id": clientID, "redirect_uri": callback, "scope": scopes, "state": state, "nonce": nonce, "code_challenge": challenge(verifier), "code_challenge_method": "S256", "identity_provider": "SignInWithApple"].map { URLQueryItem(name: $0.key, value: $0.value) }
        return url.url!
    }
    public static func authorizationCode(_ url: URL, state: String) throws -> String {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == "pocketpad", parts.host == "auth", parts.path == "/callback", parts.port == nil, parts.user == nil, parts.password == nil, parts.fragment == nil else { throw MarketplaceAuthError("Unexpected sign-in callback.") }
        let items = parts.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count, items.first(where: { $0.name == "state" })?.value == state else { throw MarketplaceAuthError("Sign-in state did not match. Please sign in again.") }
        guard !items.contains(where: { $0.name == "error" }), let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw MarketplaceAuthError("Sign-in was not completed.") }
        return code
    }
}

/// No redirects: bearer credentials and token POSTs must stay at the intended origin.
private final class NoAuthRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
public enum MarketplaceHTTP {
    public static func send(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: NoAuthRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw MarketplaceAuthError("Invalid server response.") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2 * 1024 * 1024 else { throw MarketplaceAuthError("Server response is too large.") }
            data.append(byte)
        }
        return (data, response.statusCode)
    }
}

public struct MarketplaceIdentity: Codable, Equatable {
    public let issuer: String
    public let subject: String
}
struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expires: Date
    var identity: MarketplaceIdentity
}
private enum AccountKeychain {
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.pocketpad.marketplace.oauth", kSecAttrAccount as String: MarketplaceOAuth.clientID, kSecUseDataProtectionKeychain as String: true] }
    static func read() throws -> OAuthTokens? {
        var q = query; q[kSecReturnData as String] = true
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw MarketplaceAuthError("Unable to read account credentials from Keychain.") }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }
    static func write(_ tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw MarketplaceAuthError("Unable to save account credentials in Keychain.") }; return
        }
        guard status == errSecSuccess else { throw MarketplaceAuthError("Unable to update account credentials in Keychain.") }
    }
    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MarketplaceAuthError("Unable to clear account credentials from Keychain.") }
    }
}

public enum CognitoIDToken {
    // ASN.1 DER RSAPublicKey, imported by Security for RS256 verification.
    private static func der(_ tag: UInt8, _ data: Data) -> Data {
        let length = data.count < 128 ? [UInt8(data.count)] : data.count < 256 ? [0x81, UInt8(data.count)] : [0x82, UInt8(data.count >> 8), UInt8(data.count & 255)]
        return Data([tag] + length) + data
    }
    private static func integer(_ data: Data) -> Data { der(2, data.first.map { $0 >= 128 } == true ? Data([0]) + data : data) }
    public static func validate(_ token: String, jwks: Data, nonce: String?, expectedSubject: String? = nil, now: Date = Date()) throws -> MarketplaceIdentity {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let headerData = MarketplaceOAuth.decode64(parts[0]), let claimsData = MarketplaceOAuth.decode64(parts[1]), let signature = MarketplaceOAuth.decode64(parts[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any], header["alg"] as? String == "RS256", let kid = header["kid"] as? String,
              let set = try JSONSerialization.jsonObject(with: jwks) as? [String: Any], let keys = set["keys"] as? [[String: Any]],
              let key = keys.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" && $0["alg"] as? String == "RS256" && $0["use"] as? String == "sig" }),
              let n = key["n"] as? String, let e = key["e"] as? String, let modulus = MarketplaceOAuth.decode64(n), let exponent = MarketplaceOAuth.decode64(e), modulus.count >= 256,
              let publicKey = SecKeyCreateWithData(der(0x30, integer(modulus) + integer(exponent)) as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, Data((parts[0] + "." + parts[1]).utf8) as CFData, signature as CFData, nil),
              let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
              claims["iss"] as? String == MarketplaceOAuth.issuer, claims["aud"] as? String == MarketplaceOAuth.clientID, claims["token_use"] as? String == "id",
              let exp = claims["exp"] as? Double, exp > now.timeIntervalSince1970,
              let iat = claims["iat"] as? Double, iat <= now.timeIntervalSince1970 + 60,
              let sub = claims["sub"] as? String, !sub.isEmpty,
              nonce == nil || claims["nonce"] as? String == nonce,
              expectedSubject == nil || sub == expectedSubject else { throw MarketplaceAuthError("Could not verify the sign-in identity. Please sign in again.") }
        return MarketplaceIdentity(issuer: MarketplaceOAuth.issuer, subject: sub)
    }
}

public actor MarketplaceAuth {
    public static let shared = MarketplaceAuth()
    private var refresh: Task<String, Error>?
    private let readCredentials: () throws -> OAuthTokens?
    private let writeCredentials: (OAuthTokens) throws -> Void
    private let clearCredentials: () throws -> Void
    private let exchangeTokens: ([String: String], String?, String?) async throws -> OAuthTokens
    private var generation = UUID()
    private var signingIn: UUID?
    public init() {
        readCredentials = AccountKeychain.read; writeCredentials = AccountKeychain.write; clearCredentials = AccountKeychain.clear
        exchangeTokens = { try await Self.exchange($0, nonce: $1, subject: $2) }
    }
    init(read: @escaping () throws -> OAuthTokens?, write: @escaping (OAuthTokens) throws -> Void, clear: @escaping () throws -> Void, exchange: @escaping ([String: String], String?, String?) async throws -> OAuthTokens) {
        readCredentials = read; writeCredentials = write; clearCredentials = clear; exchangeTokens = exchange
    }
    public func identity() throws -> MarketplaceIdentity? { try readCredentials()?.identity }
    private static func exchange(_ fields: [String: String], nonce: String?, subject: String?) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: MarketplaceOAuth.domain + "/oauth2/token")!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = MarketplaceOAuth.form(fields.merging(["client_id": MarketplaceOAuth.clientID]) { a, _ in a })
        let (data, status) = try await MarketplaceHTTP.send(request)
        guard status == 200 else { throw MarketplaceAuthError("Sign-in expired or was rejected. Please sign in again.") }
        struct Response: Decodable { let access_token: String; let refresh_token: String; let id_token: String; let expires_in: Double; let token_type: String }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.token_type.lowercased() == "bearer", !response.access_token.isEmpty, !response.refresh_token.isEmpty, response.expires_in > 0 else { throw MarketplaceAuthError("Invalid sign-in response.") }
        let (jwks, keyStatus) = try await MarketplaceHTTP.send(URLRequest(url: URL(string: MarketplaceOAuth.issuer + "/.well-known/jwks.json")!))
        guard keyStatus == 200 else { throw MarketplaceAuthError("Unable to verify sign-in keys.") }
        let identity = try CognitoIDToken.validate(response.id_token, jwks: jwks, nonce: nonce, expectedSubject: subject)
        return OAuthTokens(accessToken: response.access_token, refreshToken: response.refresh_token, expires: Date().addingTimeInterval(min(response.expires_in, 900)), identity: identity)
    }
    public func signIn(code: String, verifier: String, nonce: String) async throws {
        guard refresh == nil, signingIn == nil else { throw MarketplaceAuthError("Account update in progress. Try again shortly.") }
        let operation = UUID(); generation = operation; signingIn = operation
        defer { if signingIn == operation { signingIn = nil } }
        let tokens = try await exchangeTokens(["grant_type": "authorization_code", "code": code, "redirect_uri": MarketplaceOAuth.callback, "code_verifier": verifier], nonce, nil)
        guard generation == operation else { throw CancellationError() }
        try writeCredentials(tokens)
    }
    public func accessToken() async throws -> String {
        guard signingIn == nil else { throw MarketplaceAuthError("Sign-in is still in progress.") }
        if let refresh { return try await refresh.value }
        guard var tokens = try readCredentials() else { throw MarketplaceAuthError("Sign in to publish a layout.") }
        if tokens.expires.timeIntervalSinceNow > 60 { return tokens.accessToken }
        guard let refreshToken = tokens.refreshToken else { throw MarketplaceAuthError("Sign in again to reconnect your account.") }
        // Persist consumed state BEFORE sending: a crash/timeout must never replay a rotating token.
        tokens.refreshToken = nil; try writeCredentials(tokens)
        let operation = generation
        let task = Task<String, Error> {
            do {
                let next = try await self.exchangeTokens(["grant_type": "refresh_token", "refresh_token": refreshToken], nil, tokens.identity.subject)
                guard operation == self.generation else { throw CancellationError() }
                try self.writeCredentials(next)
                return next.accessToken
            } catch {
                if operation == self.generation { try? self.clearCredentials() }
                throw MarketplaceAuthError("Account refresh could not be completed safely. Please sign in again.")
            }
        }
        refresh = task
        defer { if operation == generation { refresh = nil } }
        return try await task.value
    }
    public func signOut() async throws {
        generation = UUID(); signingIn = nil; refresh?.cancel(); refresh = nil
        let tokens = try? readCredentials()
        try clearCredentials()
        if let token = tokens?.refreshToken {
            var request = URLRequest(url: URL(string: MarketplaceOAuth.domain + "/oauth2/revoke")!)
            request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = MarketplaceOAuth.form(["token": token, "client_id": MarketplaceOAuth.clientID])
            do {
                let (_, status) = try await MarketplaceHTTP.send(request)
                guard status == 200 else { throw MarketplaceAuthError("Revocation rejected.") }
            } catch { throw MarketplaceAuthError("Signed out locally, but server revocation could not be confirmed.") }
        }
    }
}
