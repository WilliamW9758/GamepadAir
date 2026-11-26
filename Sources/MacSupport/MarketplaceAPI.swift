import Foundation
#if canImport(GamepadCore)
import GamepadCore
#endif

public struct MarketplaceGame: Decodable, Identifiable, Equatable {
    public let id: String
    public let slug: String
    public let name: String
}
public struct MarketplaceTag: Decodable, Identifiable {
    public let id: String
    public let slug: String
    public let label: String
}
public struct MarketplaceAccount: Decodable { public let id: String }
public struct OwnedListing: Decodable, Identifiable {
    public let id: String
    public let title: String
    public let status: String
    public let latest_revision: Int
    public let published_revision: Int?
}
public struct MarketplaceSubmission: Decodable {
    public let id: String
    public let revision: Int
    public let review_status: String
}
public struct MarketplaceAPI {
    public let baseURL: URL
    var send: (URLRequest) async throws -> (Data, Int) = MarketplaceHTTP.send
    var token: () async throws -> String = { try await MarketplaceAuth.shared.accessToken() }
    var signedIn: () async throws -> Bool = { try await MarketplaceAuth.shared.identity() != nil }
    public init(baseURL: String) throws {
        guard let url = URL(string: baseURL), let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host)) else { throw MarketplaceAuthError("Use an HTTPS server address, or HTTP on localhost for development.") }
        self.baseURL = url
    }
    public func request(_ path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = true, query: [URLQueryItem] = [], timeout: TimeInterval = 30) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated { request.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization") }
        let data: Data; let status: Int
        do { (data, status) = try await send(request) }
        catch {
            if method != "GET" { throw MarketplaceAuthError("The server response was interrupted. The request may have been accepted. Refresh its status before trying again.") }
            throw error
        }
        guard (200..<300).contains(status) else {
            switch status {
            case 401: throw MarketplaceAuthError("Your session has expired. Please sign in to continue.", requiresSignIn: true)
            case 403: throw MarketplaceAuthError("This account is not allowed to perform this action.")
            case 409: throw MarketplaceAuthError("This listing changed. Refresh Your layouts before submitting a revision.")
            case 404: throw MarketplaceAuthError("This item or feature is unavailable on this server. Refresh and try again.")
            case 422: throw MarketplaceAuthError("The server rejected this request. Check the supplied information.")
            case 429: throw MarketplaceAuthError("Too many requests. Please wait before trying again.")
            case 503: throw MarketplaceAuthError("This service is temporarily unavailable. Please try again later.")
            default: throw MarketplaceAuthError("The server returned HTTP \(status).")
            }
        }
        return data
    }
    public func me() async throws -> MarketplaceAccount { try JSONDecoder().decode(MarketplaceAccount.self, from: await request("v1/me")) }
    public func owned() async throws -> [OwnedListing] {
        struct Page: Decodable { let items: [OwnedListing] }
        return try JSONDecoder().decode(Page.self, from: await request("v1/me/layouts")).items
    }
    public func games(query: String = "") async throws -> [MarketplaceGame] {
        struct Page: Decodable { let items: [MarketplaceGame] }
        return try JSONDecoder().decode(Page.self, from: await request("v1/games", authenticated: false, query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "20")])).items
    }
    public func tags() async throws -> [MarketplaceTag] {
        struct Page: Decodable { let items: [MarketplaceTag] }
        return try JSONDecoder().decode(Page.self, from: await request("v1/tags", authenticated: false)).items
    }
    public func submit(document: LayoutDocument, title: String, description: String, gameID: String? = nil, tags: [String] = []) async throws -> MarketplaceSubmission {
        guard tags.count <= 10, Set(tags).count == tags.count else { throw MarketplaceAuthError("Choose up to 10 distinct use-case tags.") }
        struct Body: Encodable { let title: String; let description: String; let game_id: String?; let tags: [String]; let document: LayoutDocument }
        try document.validate()
        let body = try JSONEncoder().encode(Body(title: title, description: description, game_id: gameID, tags: tags, document: document))
        return try JSONDecoder().decode(MarketplaceSubmission.self, from: await request("v1/layouts", method: "POST", body: body))
    }
    public func revise(_ listing: OwnedListing, document: LayoutDocument) async throws -> MarketplaceSubmission {
        struct Body: Encodable { let expected_latest_revision: Int; let document: LayoutDocument }
        try document.validate()
        let body = try JSONEncoder().encode(Body(expected_latest_revision: listing.latest_revision, document: document))
        return try JSONDecoder().decode(MarketplaceSubmission.self, from: await request("v1/layouts/\(listing.id)/revisions", method: "PUT", body: body))
    }
    public func revision(_ listing: OwnedListing) async throws -> LayoutDocument {
        let data = try await request("v1/me/layouts/\(listing.id)/revisions/\(listing.latest_revision)")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let document = object["document"] else { throw MarketplaceAuthError("Missing layout document.") }
        return try LayoutDocument.decode(JSONSerialization.data(withJSONObject: document))
    }
    public func remove(_ listing: OwnedListing) async throws { _ = try await request("v1/layouts/\(listing.id)", method: "DELETE") }
}

public struct PublicListing: Decodable, Identifiable {
    public struct Revision: Decodable { public let number: Int; public let digest: String }
    public let id: String
    public let title: String
    public let description: String
    public let input_type: String
    public let creator_id: String?
    public let creator_name: String?
    public var creatorName: String {
        if let name = creator_name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return creator_id.map { "Creator " + String($0.prefix(8)) } ?? "Community"
    }
    public let current_revision: Revision
}
public struct MarketplaceCatalogPage: Decodable {
    public let items: [PublicListing]
    public let next_cursor: String?
}
extension MarketplaceAPI {
    public func creatorLayouts(_ creator: String, cursor: String? = nil) async throws -> MarketplaceCatalogPage {
        var next = cursor
        var visited = Set<String>()
        while true {
            try Task.checkCancellation()
            var query = [URLQueryItem(name: "creator_id", value: creator), URLQueryItem(name: "limit", value: "100")]
            if let next {
                guard visited.insert(next).inserted else { throw MarketplaceAuthError("The server repeated a catalog page. Try again later.") }
                query.append(URLQueryItem(name: "cursor", value: next))
            }
            let page = try JSONDecoder().decode(MarketplaceCatalogPage.self, from: await request("v1/layouts", authenticated: signedIn(), query: query))
            // Older servers ignore creator_id. Filter their paginated results locally as a fallback.
            let items = page.items.filter { $0.creator_id == creator }
            if !items.isEmpty || page.next_cursor == nil { return MarketplaceCatalogPage(items: items, next_cursor: page.next_cursor) }
            next = page.next_cursor
        }
    }
    public func browse() async throws -> [PublicListing] {
        struct Page: Decodable { let items: [PublicListing] }
        return try JSONDecoder().decode(Page.self, from: await request("v1/layouts", authenticated: try await signedIn())).items
    }
    public func download(_ listing: PublicListing) async throws -> LocalLayout {
        let data = try await request("v1/layouts/\(listing.id)/revisions/\(listing.current_revision.number)/download", authenticated: try await signedIn())
        return try LocalLayout(document: LayoutDocument.decode(data), provenance: LayoutProvenance(publicationID: listing.id, revisionID: String(listing.current_revision.number), digest: listing.current_revision.digest))
    }
}

public enum MarketplaceReportReason: String, CaseIterable, Codable {
    case abuse, hate, sexual, violence, personalInformation = "personal_information", spam, other
    public var title: String {
        switch self {
        case .abuse: return "Abuse or harassment"
        case .hate: return "Hateful content"
        case .sexual: return "Sexual content"
        case .violence: return "Violence"
        case .personalInformation: return "Personal information"
        case .spam: return "Spam"
        case .other: return "Other"
        }
    }
}
public struct MarketplaceReview: Decodable {
    public let review_status: String
    public let review_reason: String?
}
public struct MarketplaceDeletion: Decodable {
    public let status: String
    public let apple_revocation: String?
    public let apple_revocation_url: String?
}
extension MarketplaceAPI {
    public func report(_ listing: PublicListing, reason: MarketplaceReportReason, explanation: String) async throws {
        guard explanation.count <= 2000 else { throw MarketplaceAuthError("Keep the explanation within 2,000 characters.") }
        struct Body: Encodable { let revision: Int; let reason: MarketplaceReportReason; let explanation: String }
        let body = try JSONEncoder().encode(Body(revision: listing.current_revision.number, reason: reason, explanation: explanation))
        _ = try await request("v1/layouts/\(listing.id)/reports", method: "POST", body: body, authenticated: signedIn())
    }
    public func blocks() async throws -> [String] {
        struct Response: Decodable { let creator_ids: [String] }
        return try JSONDecoder().decode(Response.self, from: await request("v1/me/blocks")).creator_ids
    }
    public func block(_ creator: String, blocked: Bool) async throws {
        _ = try await request("v1/me/blocks/\(creator)", method: blocked ? "PUT" : "DELETE")
    }
    public func review(_ listing: OwnedListing) async throws -> MarketplaceReview {
        try JSONDecoder().decode(MarketplaceReview.self, from: await request("v1/me/layouts/\(listing.id)/revisions/\(listing.latest_revision)"))
    }
    public func deletionStatus() async throws -> MarketplaceDeletion {
        try JSONDecoder().decode(MarketplaceDeletion.self, from: await request("v1/me/deletion", timeout: 5))
    }
    /// The captured access token lives only for this operation. Never refresh or persist it.
    public func waitForDeletion(accessToken: String, attempts: Int = 45, pause: () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }) async throws -> MarketplaceDeletion {
        var client = self
        client.token = { accessToken }
        let deadline = Date().addingTimeInterval(90)
        var result = try await client.deletionStatus()
        for _ in 0..<max(0, attempts) {
            guard result.status == "pending", Date() < deadline else { return result }
            try await pause()
            try Task.checkCancellation()
            result = try await client.deletionStatus()
        }
        return result
    }
    public func deleteAccount() async throws -> MarketplaceDeletion {
        try JSONDecoder().decode(MarketplaceDeletion.self, from: await request("v1/me/deletion", method: "POST", body: Data(#"{"confirmation":"delete_my_account"}"#.utf8)))
    }
}
