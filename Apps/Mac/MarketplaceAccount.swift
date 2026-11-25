import SwiftUI
import AuthenticationServices

@MainActor final class MarketplaceAccountModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var identity: MarketplaceIdentity?
    @Published var accountID: String?
    @Published var busy = false
    @Published var notice: String?
    @Published var listings: [OwnedListing] = []
    @Published var endpoint = UserDefaults.standard.string(forKey: "marketplace-api-url") ?? "http://127.0.0.1:8001"
    private var activeEndpoint = UserDefaults.standard.string(forKey: "marketplace-api-url") ?? "http://127.0.0.1:8001"
    private var browser: ASWebAuthenticationSession?
    var api: MarketplaceAPI { get throws { try MarketplaceAPI(baseURL: activeEndpoint) } }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
    private func authenticateBrowser(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "pocketpad") { [weak self] callback, error in
                Task { @MainActor in self?.browser = nil }
                if let error { continuation.resume(throwing: error) }
                else if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: MarketplaceAuthError("Sign-in did not return a callback.")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            browser = session
            if !session.start() { browser = nil; continuation.resume(throwing: MarketplaceAuthError("Could not open the sign-in browser.")) }
        }
    }
    func perform(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true; notice = nil
        Task {
            defer { busy = false }
            do { try await operation() }
            catch {
                notice = error.localizedDescription
                if (try? await MarketplaceAuth.shared.identity()) == nil {
                    identity = nil; accountID = nil; listings = []
                }
            }
        }
    }
    func restore() { perform {
        self.identity = try await MarketplaceAuth.shared.identity()
        if self.identity != nil { try await self.loadAccount() }
    } }
    func loadAccount() async throws {
        let client = try api
        accountID = try await client.me().id
        listings = try await client.owned()
    }
    func signIn() { perform {
        let state = try MarketplaceOAuth.random(), nonce = try MarketplaceOAuth.random(), verifier = try MarketplaceOAuth.random()
        let callback = try await self.authenticateBrowser(MarketplaceOAuth.authorizationURL(state: state, nonce: nonce, verifier: verifier))
        let code = try MarketplaceOAuth.authorizationCode(callback, state: state)
        try await MarketplaceAuth.shared.signIn(code: code, verifier: verifier, nonce: nonce)
        self.identity = try await MarketplaceAuth.shared.identity()
        try await self.loadAccount()
        self.notice = "Signed in. Layout submissions are reviewed before appearing publicly."
    } }
    func signOut() { perform {
        self.identity = nil; self.accountID = nil; self.listings = []
        var revocationError: Error?
        do { try await MarketplaceAuth.shared.signOut() } catch { revocationError = error }
        var url = URLComponents(string: MarketplaceOAuth.domain + "/logout")!
        url.queryItems = [URLQueryItem(name: "client_id", value: MarketplaceOAuth.clientID), URLQueryItem(name: "logout_uri", value: "pocketpad://auth/logout")]
        do {
            let callback = try await self.authenticateBrowser(url.url!)
            guard callback.absoluteString == "pocketpad://auth/logout" else { throw MarketplaceAuthError("Unexpected logout callback.") }
        } catch { self.notice = "Local credentials cleared. Browser sign-out was not completed." }
        if let revocationError { throw revocationError }
    } }
    func setEndpoint() { perform {
        _ = try MarketplaceAPI(baseURL: self.endpoint)
        self.activeEndpoint = self.endpoint
        UserDefaults.standard.set(self.endpoint, forKey: "marketplace-api-url")
        self.accountID = nil; self.listings = []
        if self.identity != nil { try await self.loadAccount() }
    } }
}

struct MarketplaceAccountView: View {
    @ObservedObject var account: MarketplaceAccountModel
    let layouts: [LocalLayout]
    @State private var selectedLayoutID = ""
    @State private var submissionLayout: LocalLayout?
    private var selectedLayout: LocalLayout? { layouts.first { $0.id == selectedLayoutID } }
    private func updateSelection() {
        if selectedLayout == nil { selectedLayoutID = "" }
    }
    let importLayout: (LayoutDocument) -> Void
    @State private var title = ""
    @State private var description = ""
    @State private var submitting = false
    @State private var revising: OwnedListing?
    @State private var removing: OwnedListing?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Your layouts").font(.title2.bold())
                    Text(account.accountID == nil ? "Sign in to share layouts. Browsing needs no account." : "Submissions are reviewed before publication.").foregroundStyle(.secondary)
                }
                Spacer()
                if account.identity == nil { Button("Sign in with Apple") { account.signIn() } }
                else { Button("Sign in again") { account.signIn() }; Button("Refresh") { account.perform { try await account.loadAccount() } }; Button("Sign out") { account.signOut() } }
            }
            if account.busy { ProgressView().controlSize(.small) }
            if let notice = account.notice { Text(notice).textSelection(.enabled).foregroundStyle(.secondary) }
            if account.accountID != nil {
                HStack {
                    Picker("Layout", selection: $selectedLayoutID) {
                        Text(layouts.isEmpty ? "No saved layouts" : "Choose a layout").tag("")
                        ForEach(layouts) { layout in
                            Text(layout.name + (layout.isPreset ? " · preset" : "") +
                                 (layouts.filter { $0.name == layout.name }.count > 1 ? " · " + String(layout.id.prefix(6)) : ""))
                                .tag(layout.id)
                        }
                    }.frame(maxWidth: 380)
                    Button("Submit layout…") {
                        submissionLayout = selectedLayout; title = selectedLayout?.name ?? ""; description = ""; submitting = true
                    }.disabled(selectedLayout == nil)
                }
                ForEach(account.listings) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.title).font(.headline)
                        Text("Revision \(item.latest_revision) · \(item.status)" + (item.published_revision.map { " · Published revision \($0)" } ?? " · Not yet public")).foregroundStyle(.secondary)
                        HStack {
                            Button("Open latest") { account.perform { importLayout(try await account.api.revision(item)) } }
                            Button("Submit selected as revision…") { submissionLayout = selectedLayout; revising = item }.disabled(selectedLayout == nil || item.status == "removed")
                            Button("Remove…", role: .destructive) { removing = item }.disabled(item.status == "removed")
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            DisclosureGroup("Server connection") {
                HStack { TextField("API base URL", text: $account.endpoint); Button("Apply") { account.setEndpoint() } }
                Text("Use the local development server until the public service is available.").font(.callout).foregroundStyle(.secondary)
            }
        }.disabled(account.busy)
        .onAppear { updateSelection() }
        .onChange(of: layouts.map(\.id)) { _, _ in updateSelection() }
        .sheet(isPresented: $submitting) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Share layout").font(.title2.bold())
                TextField("Title", text: $title)
                TextField("Description", text: $description, axis: .vertical).lineLimit(3...6)
                Text("A copy of “\(submissionLayout?.name ?? "layout")” will be submitted for review.").foregroundStyle(.secondary)
                HStack { Button("Cancel") { submitting = false }; Spacer(); Button("Submit for review") {
                    guard let submissionLayout else { return }; submitting = false
                    account.perform {
                        let result = try await account.api.submit(document: submissionLayout.document, title: title, description: description)
                        try await account.loadAccount(); account.notice = "Revision \(result.revision) submitted for review."
                    }
                }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 120 || description.count > 4000) }
            }.padding(24).frame(width: 480)
        }
        .confirmationDialog("Submit “\(submissionLayout?.name ?? "layout")” as a new revision?", isPresented: Binding(get: { revising != nil }, set: { if !$0 { revising = nil } })) {
            if let listing = revising, let submissionLayout { Button("Submit revision") { revising = nil; account.perform {
                let result = try await account.api.revise(listing, document: submissionLayout.document)
                try await account.loadAccount(); account.notice = "Revision \(result.revision) submitted for review."
            } } }
        }
        .confirmationDialog("Remove this listing from the marketplace?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let listing = removing { Button("Remove listing", role: .destructive) { removing = nil; account.perform { try await account.api.remove(listing); try await account.loadAccount() } } }
        } message: { Text("Already downloaded copies remain on other devices.") }
    }
}
