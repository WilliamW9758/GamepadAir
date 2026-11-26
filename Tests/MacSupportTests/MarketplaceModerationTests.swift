import XCTest
@testable import MacSupport

final class MarketplaceModerationTests: XCTestCase {
    private let listingJSON = #"{"id":"layout-1","title":"Test","description":"Example","input_type":"gamepad","creator_id":"creator-1","current_revision":{"number":2,"digest":"abc"}}"#
    func testPublicReadsUseAuthenticationWhenSignedIn() async throws {
        var api = try MarketplaceAPI(baseURL: "http://localhost:8001")
        api.signedIn = { true }; api.token = { "test-token" }
        api.send = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return (Data((#"{"items":["# + self.listingJSON + "]}").utf8), 200)
        }
        let listings = try await api.browse()
        XCTAssertEqual(listings.first?.creator_id, "creator-1")
        api.send = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.url?.path, "/v1/layouts/layout-1/revisions/2/download")
            return (Data(), 404)
        }
        do { _ = try await api.download(listings[0]); XCTFail("Blocked downloads must fail") } catch {}
    }
    func testAnonymousReportPayloadAndLength() async throws {
        var api = try MarketplaceAPI(baseURL: "http://localhost:8001")
        api.signedIn = { false }; api.token = { XCTFail("Anonymous report must not request credentials"); return "" }
        var calls = 0
        api.send = { request in
            calls += 1
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/layouts/layout-1/reports")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["reason"] as? String, "personal_information")
            XCTAssertEqual(body["revision"] as? Int, 2)
            return (Data(#"{"status":"received"}"#.utf8), 202)
        }
        let listing = try JSONDecoder().decode(PublicListing.self, from: Data(listingJSON.utf8))
        try await api.report(listing, reason: .personalInformation, explanation: "Private information")
        do { try await api.report(listing, reason: .other, explanation: String(repeating: "x", count: 2001)); XCTFail() } catch {}
        XCTAssertEqual(calls, 1)
    }
    func testBlocksAndDeletionContracts() async throws {
        var api = try MarketplaceAPI(baseURL: "http://localhost:8001")
        api.token = { "token" }
        var methods: [String] = []
        api.send = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            methods.append(request.httpMethod!)
            if request.url!.path.hasSuffix("/deletion") {
                XCTAssertEqual(request.httpBody, Data(#"{"confirmation":"delete_my_account"}"#.utf8))
                return (Data(#"{"status":"pending","apple_revocation":"manual_required","apple_revocation_url":"https://account.apple.com/"}"#.utf8), 202)
            }
            return (Data(), 204)
        }
        try await api.block("creator-1", blocked: true)
        try await api.block("creator-1", blocked: false)
        let deletion = try await api.deleteAccount()
        XCTAssertEqual(deletion.status, "pending")
        XCTAssertEqual(deletion.apple_revocation, "manual_required")
        XCTAssertEqual(methods, ["PUT", "DELETE", "POST"])
    }
    func testRecentSignInAndUnavailableErrors() async throws {
        let url = MarketplaceOAuth.authorizationURL(state: "s", nonce: "n", verifier: "v", reauthenticate: true)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "prompt" }?.value, "login")
        var api = try MarketplaceAPI(baseURL: "http://localhost:8001")
        api.token = { "token" }
        api.send = { _ in (Data(), 401) }
        do { _ = try await api.deleteAccount(); XCTFail() }
        catch { XCTAssertTrue((error as? MarketplaceAuthError)?.requiresSignIn == true) }
        api.send = { _ in (Data(), 503) }
        do { _ = try await api.blocks(); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("temporarily unavailable")) }
    }
    func testReviewFeedbackAndLegacyCreator() throws {
        let review = try JSONDecoder().decode(MarketplaceReview.self, from: Data(#"{"review_status":"rejected","review_reason":"Remove personal information"}"#.utf8))
        XCTAssertEqual(review.review_reason, "Remove personal information")
        let legacy = listingJSON.replacingOccurrences(of: #""creator_id":"creator-1","#, with: "")
        XCTAssertNil(try JSONDecoder().decode(PublicListing.self, from: Data(legacy.utf8)).creator_id)
    }
    func testDeletionCleanupDoesNotDependOnRevocationNetwork() async throws {
        var stored = OAuthTokens(accessToken: "test", refreshToken: "refresh", expires: .distantFuture, identity: MarketplaceIdentity(issuer: "issuer", subject: "subject")) as OAuthTokens?
        let auth = MarketplaceAuth(read: { stored }, write: { stored = $0 }, clear: { stored = nil }, exchange: { _, _, _ in XCTFail(); throw CancellationError() })
        try await auth.clearLocalCredentials()
        let identity = try await auth.identity()
        XCTAssertNil(identity)
        XCTAssertNil(stored)
    }
}
