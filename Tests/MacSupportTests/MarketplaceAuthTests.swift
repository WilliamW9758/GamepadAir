import XCTest
import Security
@testable import MacSupport

final class MarketplaceAuthTests: XCTestCase {
    func testPKCEVectorAndCallbackValidation() throws {
        XCTAssertEqual(MarketplaceOAuth.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(try MarketplaceOAuth.authorizationCode(URL(string: "pocketpad://auth/callback?state=ok&code=abc")!, state: "ok"), "abc")
        for value in ["pocketpad://auth/callback?state=wrong&code=abc", "pocketpad://auth/callback?state=ok&state=ok&code=abc", "pocketpad://auth/logout?state=ok&code=abc", "pocketpad://auth/callback?state=ok&code=abc#fragment", "pocketpad://user@auth/callback?state=ok&code=abc", "pocketpad://auth/callback?state=ok&error=denied"] {
            XCTAssertThrowsError(try MarketplaceOAuth.authorizationCode(URL(string: value)!, state: "ok"))
        }
        XCTAssertEqual(try MarketplaceOAuth.random().count, 43)
    }
    func testEndpointRejectsInsecureRemoteAndCredentials() throws {
        XCTAssertNoThrow(try MarketplaceAPI(baseURL: "http://127.0.0.1:8001"))
        XCTAssertNoThrow(try MarketplaceAPI(baseURL: "https://example.com"))
        for value in ["http://example.com", "https://user:pass@example.com", "https://example.com?token=x", "file:///tmp/auth"] { XCTAssertThrowsError(try MarketplaceAPI(baseURL: value)) }
    }
    func testRS256IdentityClaimsAndTampering() throws {
        let key = try XCTUnwrap(SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(key))
        let der = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil)) as Data
        var offset = 0
        func read() -> Data {
            offset += 1
            var length = Int(der[offset]); offset += 1
            if length > 127 { let count = length & 127; length = 0; for _ in 0..<count { length = length * 256 + Int(der[offset]); offset += 1 } }
            let value = der.subdata(in: offset..<offset+length); offset += length; return value
        }
        // Strip sequence header, then decode integer fields.
        offset = der[1] == 0x82 ? 4 : 3
        let modulus = read(), exponent = read()
        let jwks = try JSONSerialization.data(withJSONObject: ["keys": [["kid":"test", "kty":"RSA", "alg":"RS256", "use":"sig", "n":MarketplaceOAuth.base64(modulus), "e":MarketplaceOAuth.base64(exponent)]]])
        let now = Date()
        let claims: [String: Any] = ["iss":MarketplaceOAuth.issuer, "aud":MarketplaceOAuth.clientID, "sub":"stable-subject", "token_use":"id", "nonce":"nonce", "exp":now.timeIntervalSince1970+900, "iat":now.timeIntervalSince1970]
        func token(_ claims: [String: Any]) throws -> String {
            let header = MarketplaceOAuth.base64(try JSONSerialization.data(withJSONObject: ["alg":"RS256", "kid":"test"]))
            let body = MarketplaceOAuth.base64(try JSONSerialization.data(withJSONObject: claims))
            let payload = header + "." + body
            let signature = try XCTUnwrap(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(payload.utf8) as CFData, nil)) as Data
            return payload + "." + MarketplaceOAuth.base64(signature)
        }
        XCTAssertEqual(try CognitoIDToken.validate(token(claims), jwks: jwks, nonce: "nonce").subject, "stable-subject")
        for (field, value) in [("iss", "https://attacker.test"), ("aud", "wrong-client"), ("token_use", "access"), ("nonce", "wrong")] {
            var modified = claims; modified[field] = value
            XCTAssertThrowsError(try CognitoIDToken.validate(token(modified), jwks: jwks, nonce: "nonce"))
        }
        XCTAssertThrowsError(try CognitoIDToken.validate(token(claims), jwks: jwks, nonce: "nonce", expectedSubject: "different-account"))
        XCTAssertThrowsError(try CognitoIDToken.validate(token(claims), jwks: jwks, nonce: "nonce", now: now.addingTimeInterval(1000)))
        let signed = try token(claims)
        XCTAssertThrowsError(try CognitoIDToken.validate(String(signed.dropLast(8)) + "AAAAAAAA", jwks: jwks, nonce: "nonce"))
    }
    func testConcurrentRefreshConsumesOnceAndPersistsRotation() async throws {
        final class Store { var tokens: OAuthTokens?; var calls = 0 }
        let store = Store()
        let identity = MarketplaceIdentity(issuer: MarketplaceOAuth.issuer, subject: "test")
        store.tokens = OAuthTokens(accessToken: "old", refreshToken: "refresh-old", expires: .distantPast, identity: identity)
        let auth = MarketplaceAuth(read: { store.tokens }, write: { store.tokens = $0 }, clear: { store.tokens = nil }) { fields, _, _ in
            store.calls += 1
            XCTAssertNil(store.tokens?.refreshToken)
            XCTAssertEqual(fields["refresh_token"], "refresh-old")
            try await Task.sleep(nanoseconds: 30_000_000)
            return OAuthTokens(accessToken: "new", refreshToken: "refresh-new", expires: Date().addingTimeInterval(900), identity: identity)
        }
        async let a = auth.accessToken()
        async let b = auth.accessToken()
        let values = try await [a,b]
        XCTAssertEqual(values, ["new", "new"]); XCTAssertEqual(store.calls, 1); XCTAssertEqual(store.tokens?.refreshToken, "refresh-new")
    }
    func testAmbiguousRefreshCannotReplay() async throws {
        final class Store { var tokens: OAuthTokens?; var calls = 0 }
        let store = Store()
        store.tokens = OAuthTokens(accessToken: "old", refreshToken: "spent", expires: .distantPast, identity: MarketplaceIdentity(issuer: MarketplaceOAuth.issuer, subject: "test"))
        let auth = MarketplaceAuth(read: { store.tokens }, write: { store.tokens = $0 }, clear: { store.tokens = nil }) { _,_,_ in store.calls += 1; throw URLError(.timedOut) }
        for _ in 0..<2 { do { _ = try await auth.accessToken(); XCTFail("Expected sign-in required") } catch {} }
        XCTAssertEqual(store.calls, 1); XCTAssertNil(store.tokens)
    }
    func testLogoutDuringRefreshCannotRestoreCredentials() async throws {
        final class Store { var tokens: OAuthTokens? }
        let store = Store()
        let identity = MarketplaceIdentity(issuer: MarketplaceOAuth.issuer, subject: "test")
        store.tokens = OAuthTokens(accessToken: "old", refreshToken: "old-refresh", expires: .distantPast, identity: identity)
        let auth = MarketplaceAuth(read: { store.tokens }, write: { store.tokens = $0 }, clear: { store.tokens = nil }) { _,_,_ in
            // Deliberately ignore cancellation, as an already delivered HTTP response may do.
            try? await Task.sleep(nanoseconds: 100_000_000)
            return OAuthTokens(accessToken: "new", refreshToken: "rotated", expires: Date().addingTimeInterval(900), identity: identity)
        }
        let request = Task { try await auth.accessToken() }
        try await Task.sleep(nanoseconds: 20_000_000)
        try await auth.signOut()
        do { _ = try await request.value; XCTFail("Logout must invalidate the pending response") } catch {}
        XCTAssertNil(store.tokens)
    }
    func testFailedKeychainWriteNeverSendsRefresh() async throws {
        var exchanges = 0
        let expired = OAuthTokens(accessToken: "old", refreshToken: "refresh", expires: .distantPast, identity: MarketplaceIdentity(issuer: MarketplaceOAuth.issuer, subject: "test"))
        let auth = MarketplaceAuth(read: { expired }, write: { _ in throw MarketplaceAuthError("Locked keychain") }, clear: {}) { _,_,_ in exchanges += 1; return expired }
        do { _ = try await auth.accessToken(); XCTFail("Expected storage failure") } catch {}
        XCTAssertEqual(exchanges, 0)
    }

}
