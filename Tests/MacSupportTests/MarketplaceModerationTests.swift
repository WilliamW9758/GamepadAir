import XCTest
import GamepadCore
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
    func testCreatorPageUsesFilterAndCursorWithPublicName() async throws {
        var api = try MarketplaceAPI(baseURL: "http://localhost:8001")
        api.signedIn = { false }
        let named = listingJSON.replacingOccurrences(of: #""title":"Test""#, with: #""creator_name":"River","title":"Test""#)
        api.send = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "creator_id" }?.value, "creator-1")
            XCTAssertEqual(query.first { $0.name == "cursor" }?.value, "a+b/=")
            return (Data((#"{"items":["# + named + #"],"next_cursor":"next"}"#).utf8), 200)
        }
        let page = try await api.creatorLayouts("creator-1", cursor: "a+b/=")
        XCTAssertEqual(page.items.first?.creatorName, "River")
        XCTAssertEqual(page.next_cursor, "next")
        api.send = { _ in (Data((#"{"items":["# + named + "]}").utf8), 200) }
        let other = try await api.creatorLayouts("other", cursor: "a+b/=")
        XCTAssertTrue(other.items.isEmpty, "Never show another creator’s work if the server ignores the filter")
    }
    func testCreatorPageFallbackScansOlderServerPages() async throws {
        var api = try MarketplaceAPI(baseURL: "http://localhost:8001")
        api.signedIn = { false }
        var calls = 0
        api.send = { request in
            calls += 1
            if calls == 1 { return (Data(#"{"items":[],"next_cursor":"page-two"}"#.utf8), 200) }
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cursor" }?.value, "page-two")
            return (Data((#"{"items":["# + self.listingJSON + "]}").utf8), 200)
        }
        let page = try await api.creatorLayouts("creator-1")
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(calls, 2)
        api.send = { _ in (Data(#"{"items":[],"next_cursor":"repeated"}"#.utf8), 200) }
        do { _ = try await api.creatorLayouts("creator-1"); XCTFail("Repeated cursors must terminate") } catch {}
    }
    func testDeletionWaitUsesCapturedTokenUntilComplete() async throws {
        var api = try MarketplaceAPI(baseURL: "http://localhost:8001")
        api.token = { XCTFail("Must not read or refresh cleared credentials"); return "" }
        var requests = 0, pauses = 0
        api.send = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer memory-only")
            XCTAssertEqual(request.timeoutInterval, 5)
            requests += 1
            return (Data((requests < 3 ? #"{"status":"pending"}"# : #"{"status":"complete"}"#).utf8), 200)
        }
        let result = try await api.waitForDeletion(accessToken: "memory-only", pause: { pauses += 1 })
        XCTAssertEqual(result.status, "complete")
        XCTAssertEqual(requests, 3)
        XCTAssertEqual(pauses, 2)
    }
    func testDeletionWaitDoesNotClaimCompletionOnTimeoutOrError() async throws {
        var api = try MarketplaceAPI(baseURL: "http://localhost:8001")
        var requests = 0
        api.send = { _ in requests += 1; return (Data(#"{"status":"pending"}"#.utf8), 200) }
        let result = try await api.waitForDeletion(accessToken: "token", attempts: 2, pause: {})
        XCTAssertEqual(result.status, "pending")
        XCTAssertEqual(requests, 3)
        api.send = { _ in (Data(), 401) }
        do { _ = try await api.waitForDeletion(accessToken: "token", pause: {}); XCTFail() } catch {}
    }
    func testSubmissionCarriesGameAndTagSlugs() async throws {
        var api = try MarketplaceAPI(baseURL: "http://localhost:8001")
        api.token = { "test-token" }
        var calls = 0
        api.send = { request in
            calls += 1
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["title"] as? String, "Farm controls")
            XCTAssertEqual(body["description"] as? String, "For farming and fishing")
            if calls == 1 {
                XCTAssertEqual(body["game_id"] as? String, "game-id")
                XCTAssertEqual(body["tags"] as? [String], ["farming", "fishing"])
            } else {
                XCTAssertNil(body["game_id"])
                XCTAssertEqual(body["tags"] as? [String], [])
            }
            return (Data(#"{"id":"listing","revision":1,"review_status":"pending"}"#.utf8), 201)
        }
        let document = LocalLayout(name: "Farm", style: .xbox).document
        let result = try await api.submit(document: document, title: "Farm controls", description: "For farming and fishing", gameID: "game-id", tags: ["farming", "fishing"])
        XCTAssertEqual(result.review_status, "pending")
        _ = try await api.submit(document: document, title: "Farm controls", description: "For farming and fishing")
        do { _ = try await api.submit(document: document, title: "Title", description: "", tags: (0..<11).map { "tag-\($0)" }); XCTFail() } catch {}
        do { _ = try await api.submit(document: document, title: "Title", description: "", tags: ["farming", "farming"]); XCTFail() } catch {}
        XCTAssertEqual(calls, 2)
    }
    func testMetadataCatalogRequestsArePublicAndSearchIsEncoded() async throws {
        var api = try MarketplaceAPI(baseURL: "http://localhost:8001")
        api.token = { XCTFail("Public catalogs do not require credentials"); return "" }
        api.send = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            if request.url!.path == "/v1/games" {
                let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertEqual(items.first { $0.name == "q" }?.value, "Farm & fish")
                XCTAssertEqual(items.first { $0.name == "limit" }?.value, "20")
                return (Data(#"{"items":[{"id":"game-id","slug":"stardew-valley","name":"Stardew Valley"}]}"#.utf8), 200)
            }
            return (Data(#"{"items":[{"id":"tag-id","slug":"farming","label":"Farming"}]}"#.utf8), 200)
        }
        let games = try await api.games(query: "Farm & fish")
        let tags = try await api.tags()
        XCTAssertEqual(games.first?.name, "Stardew Valley")
        XCTAssertEqual(tags.first?.slug, "farming")
        api.send = { _ in (Data(#"{"items":[]}"#.utf8), 200) }
        let empty = try await api.tags()
        XCTAssertTrue(empty.isEmpty)
        api.send = { _ in (Data(), 503) }
        do { _ = try await api.games(); XCTFail() } catch {}
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
