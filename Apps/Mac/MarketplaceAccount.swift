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
                let storedIdentity = try? await MarketplaceAuth.shared.identity()
                if (error as? MarketplaceAuthError)?.requiresSignIn == true || storedIdentity == nil {
                    identity = nil; accountID = nil; listings = []
                }
            }
        }
    }
    private var refreshing = false
    func updateInBackground() async {
        guard !busy, !refreshing, let startingIdentity = identity else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let client = try api
            let loadedAccount = try await client.me()
            let loadedListings = try await client.owned()
            guard !busy, identity == startingIdentity else { return }
            accountID = loadedAccount.id; listings = loadedListings
        } catch {
            guard !busy, identity == startingIdentity else { return }
            notice = error.localizedDescription
            let storedIdentity = try? await MarketplaceAuth.shared.identity()
            if (error as? MarketplaceAuthError)?.requiresSignIn == true || storedIdentity == nil {
                identity = nil; accountID = nil; listings = []
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
    let screen: PhoneScreen?
    @State private var selectedLayoutID = ""
    @State private var submissionLayout: LocalLayout?
    private var selectedLayout: LocalLayout? { layouts.first { $0.id == selectedLayoutID } }
    private func updateSelection() {
        if selectedLayout == nil { selectedLayoutID = ""; submissionLayout = nil }
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
                    Text("My submissions").font(.title2.bold())
                    Text(account.accountID == nil ? "Sign in to share layouts. Browsing needs no account." : "Submissions are reviewed before publication.").foregroundStyle(.secondary)
                }
                Spacer()
                if account.identity == nil { Button("Sign in with Apple") { account.signIn() } }
                else { Button("Sign out") { account.signOut() } }
            }
            if account.busy { ProgressView().controlSize(.small) }
            if let notice = account.notice { Text(notice).textSelection(.enabled).foregroundStyle(.secondary) }
            if account.accountID != nil {
                Button("Submit layout…") {
                    selectedLayoutID = ""; submissionLayout = nil; revising = nil
                    title = ""; description = ""; submitting = true
                }.disabled(layouts.isEmpty)
                ForEach(account.listings) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.title).font(.headline)
                        Text("Revision \(item.latest_revision) · \(item.status)" + (item.published_revision.map { " · Published revision \($0)" } ?? " · Not yet public")).foregroundStyle(.secondary)
                        HStack {
                            Button("Download a copy") { account.perform { importLayout(try await account.api.revision(item)); account.notice = "Downloaded revision \(item.latest_revision) to your layout library." } }.help("Download the newest submitted revision, including one awaiting review, as a new local copy.")
                            Button("Submit revision…") { selectedLayoutID = ""; submissionLayout = nil; revising = item; submitting = true }.disabled(layouts.isEmpty || item.status == "removed")
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
                Text(revising == nil ? "Submit layout" : "Submit a new revision").font(.title2.bold())
                if let revising { Text(revising.title).foregroundStyle(.secondary) }
                Picker("Layout", selection: $selectedLayoutID) {
                    Text("Choose a layout").tag("")
                    ForEach(layouts) { layout in
                        Text(layout.name + (layout.isPreset ? " · preset" : "") +
                             (layouts.filter { $0.name == layout.name }.count > 1 ? " · " + String(layout.id.prefix(6)) : ""))
                            .tag(layout.id)
                    }
                }.pickerStyle(.menu)
                if let submissionLayout {
                    SubmissionLayoutPreview(layout: submissionLayout, screen: screen)
                    if revising == nil {
                        TextField("Title", text: $title)
                        TextField("Description", text: $description, axis: .vertical).lineLimit(2...3)
                    }
                    Text("A copy of “\(submissionLayout.name)” will be submitted for review.").font(.callout).foregroundStyle(.secondary)
                } else {
                    RoundedRectangle(cornerRadius: 18).fill(.quaternary.opacity(0.4))
                        .overlay { Label("Choose a layout to preview", systemImage: "gamecontroller").foregroundStyle(.secondary) }
                        .frame(height: 240)
                }
                HStack {
                    Button("Cancel") { submitting = false }
                    Spacer()
                    Button("Submit for review") {
                        guard let submissionLayout else { return }
                        let listing = revising
                        let submittedTitle = title, submittedDescription = description
                        submitting = false
                        account.perform {
                            let result: MarketplaceSubmission
                            if let listing { result = try await account.api.revise(listing, document: submissionLayout.document) }
                            else { result = try await account.api.submit(document: submissionLayout.document, title: submittedTitle, description: submittedDescription) }
                            try await account.loadAccount(); account.notice = "Revision \(result.revision) submitted for review."
                        }
                    }.buttonStyle(PadActionStyle(prominent: submissionLayout != nil))
                        .disabled(submissionLayout == nil || (revising == nil && (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 120 || description.count > 4000)))
                }
            }.padding(24).frame(width: 600)
                .onChange(of: selectedLayoutID) { _, _ in submissionLayout = selectedLayout; title = selectedLayout?.name ?? "" }
        }
        .confirmationDialog("Remove this listing from the marketplace?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let listing = removing { Button("Remove listing", role: .destructive) { removing = nil; account.perform { try await account.api.remove(listing); try await account.loadAccount() } } }
        } message: { Text("Already downloaded copies remain on other devices.") }
    }
}

/// A read-only rendering of the exact document captured for submission.
struct SubmissionLayoutPreview: View {
    let layout: LocalLayout
    let screen: PhoneScreen?
    @State private var selectedModeID = ""
    private var modeID: String { layout.document.modes.contains { $0.id == selectedModeID } ? selectedModeID : layout.document.initialMode }
    private var width: Double { screen?.width ?? 912 }
    private var height: Double { screen?.height ?? 420 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(layout.effectiveInputType.title).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if layout.document.modes.count > 1 {
                    Picker("Preview mode", selection: Binding(get: { modeID }, set: { selectedModeID = $0 })) {
                        ForEach(layout.document.modes, id: \.id) { Text($0.name).tag($0.id) }
                    }.labelsHidden().frame(width: 160)
                }
            }
            GeometryReader { geometry in
                let scale = geometry.size.width / width
                let mode = layout.document.modes.first { $0.id == modeID }
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(PadAppearance.surface)
                    ForEach(LayoutGeometry.resolve(layout.document, modeID: modeID, width: width, height: height).filter { !$0.hidden }) { control in
                        ZStack {
                            if control.rectangular {
                                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15))
                                RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
                            } else if control.role == "dpad", mode?.dpadStyle == "fourWay" {
                                DPadCross().fill(.regularMaterial)
                                DPadCross().stroke(Color.primary.opacity(0.25), lineWidth: 1.5)
                            } else {
                                Circle().fill(.regularMaterial)
                                Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.5)
                            }
                            Text(control.role == "dpad" ? "✣" : control.label)
                                .font(.system(size: 14, weight: .medium)).fixedSize()
                        }
                        .frame(width: control.width * scale, height: control.height * scale)
                        .position(x: control.placement.x * geometry.size.width, y: control.placement.y * geometry.size.height)
                    }
                }.overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5) }
            }.aspectRatio(width / height, contentMode: .fit)
                .accessibilityElement(children: .ignore).accessibilityLabel("Preview of \(layout.name)")
        }
    }
}
