import Foundation
#if canImport(GamepadCore)
import GamepadCore
#endif

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
    public init(baseURL: String) throws {
        guard let url = URL(string: baseURL), let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host)) else { throw MarketplaceAuthError("Use an HTTPS server address, or HTTP on localhost for development.") }
        self.baseURL = url
    }
    public func request(_ path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = true) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated { request.setValue("Bearer " + (try await MarketplaceAuth.shared.accessToken()), forHTTPHeaderField: "Authorization") }
        let data: Data; let status: Int
        do { (data, status) = try await MarketplaceHTTP.send(request) }
        catch {
            if method != "GET" { throw MarketplaceAuthError("The server response was interrupted. Check Your layouts before submitting again; the change may have been saved.") }
            throw error
        }
        guard (200..<300).contains(status) else {
            switch status {
            case 401: throw MarketplaceAuthError("Your session was rejected. Sign out and sign in again.")
            case 403: throw MarketplaceAuthError("This account is not allowed to perform this action.")
            case 409: throw MarketplaceAuthError("This listing changed. Refresh Your layouts before submitting a revision.")
            case 422: throw MarketplaceAuthError("The server rejected this layout or its metadata.")
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
    public func submit(document: LayoutDocument, title: String, description: String) async throws -> MarketplaceSubmission {
        struct Body: Encodable { let title: String; let description: String; let tags: [String]; let document: LayoutDocument }
        try document.validate()
        let body = try JSONEncoder().encode(Body(title: title, description: description, tags: [], document: document))
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
    public let current_revision: Revision
}
extension MarketplaceAPI {
    public func browse() async throws -> [PublicListing] {
        struct Page: Decodable { let items: [PublicListing] }
        return try JSONDecoder().decode(Page.self, from: await request("v1/layouts", authenticated: false)).items
    }
    public func download(_ listing: PublicListing) async throws -> LocalLayout {
        let data = try await request("v1/layouts/\(listing.id)/revisions/\(listing.current_revision.number)/download", authenticated: false)
        return try LocalLayout(document: LayoutDocument.decode(data), provenance: LayoutProvenance(publicationID: listing.id, revisionID: String(listing.current_revision.number), digest: listing.current_revision.digest))
    }
}
