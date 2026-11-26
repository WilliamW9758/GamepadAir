import SwiftUI
import AuthenticationServices

@MainActor final class MarketplaceAccountModel: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var identity: MarketplaceIdentity?
    @Published var accountID: String?
    @Published var busy = false
    @Published var notice: String?
    @Published var listings: [OwnedListing] = []
    @Published var reviews: [String: MarketplaceReview] = [:]
    @Published var blockedCreators: Set<String> = []
    @Published var catalogVersion = UUID()
    @Published var deletionInProgress = false
    @Published var credentialCleanupFailed = false
    @Published var deletionReceipt = UserDefaults.standard.string(forKey: "marketplace-deletion-receipt")
    private var localBlocksKey: String { "marketplace-local-blocks:" + activeEndpoint }
    func refreshBlocks() async throws {
        if identity != nil { blockedCreators = Set(try await api.blocks()) }
        else { blockedCreators = Set(UserDefaults.standard.stringArray(forKey: localBlocksKey) ?? []) }
    }
    func setBlocked(_ creator: String, blocked: Bool) async throws {
        if identity != nil { try await api.block(creator, blocked: blocked) }
        if blocked { blockedCreators.insert(creator) } else { blockedCreators.remove(creator) }
        if identity == nil { UserDefaults.standard.set(Array(blockedCreators), forKey: localBlocksKey) }
        catalogVersion = UUID()
    }
    private func clearAccountState() {
        identity = nil; accountID = nil; listings = []; reviews = [:]
        blockedCreators = Set(UserDefaults.standard.stringArray(forKey: localBlocksKey) ?? [])
        catalogVersion = UUID()
    }
    private func acceptDeletion(_ result: MarketplaceDeletion) async throws {
        guard ["pending", "complete"].contains(result.status) else { throw MarketplaceAuthError("The server did not confirm a deletion request.") }
        deletionReceipt = result.status
        UserDefaults.standard.set(result.status, forKey: "marketplace-deletion-receipt")
        clearAccountState()
        // Clear credentials immediately; neither polling nor provider revocation may delay cleanup.
        do { try await MarketplaceAuth.shared.clearLocalCredentials(); credentialCleanupFailed = false }
        catch { credentialCleanupFailed = true; throw error }
        notice = nil
    }
    func deleteAccount() { perform {
        guard let original = self.identity else { throw MarketplaceAuthError("Sign in to the account you want to delete.") }
        let state = try MarketplaceOAuth.random(), nonce = try MarketplaceOAuth.random(), verifier = try MarketplaceOAuth.random()
        let callback = try await self.authenticateBrowser(MarketplaceOAuth.authorizationURL(state: state, nonce: nonce, verifier: verifier, reauthenticate: true))
        try await MarketplaceAuth.shared.signIn(code: MarketplaceOAuth.authorizationCode(callback, state: state), verifier: verifier, nonce: nonce)
        self.identity = try await MarketplaceAuth.shared.identity()
        guard self.identity == original else {
            try await MarketplaceAuth.shared.clearLocalCredentials()
            self.clearAccountState()
            throw MarketplaceAuthError("A different account was selected. No deletion was requested. Sign in to the account you want to delete.")
        }
        self.deletionInProgress = true
        defer { self.deletionInProgress = false }
        let client = try self.api
        let token = try await MarketplaceAuth.shared.accessToken()
        let accepted: MarketplaceDeletion
        do { accepted = try await client.deleteAccount() }
        catch {
            // An interrupted POST may already have queued deletion. Recover without resubmitting.
            if let status = try? await client.deletionStatus(), ["pending", "complete"].contains(status.status) { accepted = status }
            else { throw error }
        }
        try await self.acceptDeletion(accepted)
        guard accepted.status == "pending" else { return }
        do {
            let result = try await client.waitForDeletion(accessToken: token)
            if result.status == "complete" { try await self.acceptDeletion(result) }
            else { self.notice = "Deletion is taking longer than expected. Your request is saved and will continue on the server; you can close this window." }
        } catch {
            self.notice = "Your deletion request was accepted, but completion could not be confirmed. It will continue on the server; you can close this window."
        }
    } }
    func clearCredentials() { perform {
        try await MarketplaceAuth.shared.clearLocalCredentials()
        self.clearAccountState()
        self.credentialCleanupFailed = false
    } }
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
                    clearAccountState()
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
            let blocks = Set(try await client.blocks())
            guard !busy, identity == startingIdentity else { return }
            if blocks != blockedCreators { blockedCreators = blocks; catalogVersion = UUID() }
            for listing in loadedListings {
                let review = try await client.review(listing)
                guard !busy, identity == startingIdentity else { return }
                reviews[listing.id] = review
            }
        } catch {
            guard !busy, identity == startingIdentity else { return }
            notice = error.localizedDescription
            let storedIdentity = try? await MarketplaceAuth.shared.identity()
            if (error as? MarketplaceAuthError)?.requiresSignIn == true || storedIdentity == nil {
                clearAccountState()
            }
        }
    }
    func restore() { perform {
        self.identity = try await MarketplaceAuth.shared.identity()
        if self.identity != nil { try await self.loadAccount() }
        else { try await self.refreshBlocks() }
        self.catalogVersion = UUID()
    } }
    func loadAccount() async throws {
        catalogVersion = UUID()
        let client = try api
        accountID = try await client.me().id
        listings = try await client.owned()
        reviews = [:]
        for listing in listings { reviews[listing.id] = try await client.review(listing) }
        try await refreshBlocks()
        catalogVersion = UUID()
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
        defer { self.catalogVersion = UUID() }
        self.clearAccountState()
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
        self.reviews = [:]; self.blockedCreators = []; self.catalogVersion = UUID()
        UserDefaults.standard.set(self.endpoint, forKey: "marketplace-api-url")
        self.accountID = nil; self.listings = []
        if self.identity != nil { try await self.loadAccount() }
        else { try await self.refreshBlocks() }
        self.catalogVersion = UUID()
    } }
}

struct MarketplaceAccountView: View {
    @ObservedObject var account: MarketplaceAccountModel
    let layouts: [LocalLayout]
    let screen: PhoneScreen?
    let openCreator: (String) -> Void
    let importLayout: (LayoutDocument) -> Void
    @State private var submitting = false
    @State private var revising: OwnedListing?
    @State private var removing: OwnedListing?
    @State private var deleting = false
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
            if let receipt = account.deletionReceipt {
                VStack(alignment: .leading, spacing: 8) {
                    Text(receipt == "complete" ? "Account deletion completed" : "Account deletion requested").font(.headline)
                    Text(receipt == "complete" ? "The server confirmed completion." : "Your uploads are hidden. Account erasure is queued; completion has not been confirmed.")
                    Text("Local layouts and copies downloaded by others remain. To remove Apple authorization, open Sign-In and Security → Sign in with Apple in your Apple Account, select this app, and stop using Sign in with Apple.")
                    Button("Dismiss notice") {
                        account.deletionReceipt = nil
                        UserDefaults.standard.removeObject(forKey: "marketplace-deletion-receipt")
                    }
                    Link("Open Apple Account", destination: URL(string: "https://account.apple.com/")!)
                    if account.credentialCleanupFailed { Button("Retry credential cleanup") { account.clearCredentials() } }
                }.font(.callout).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
            DisclosureGroup("Blocked creators (\(account.blockedCreators.count))") {
                Text(account.identity == nil ? "Blocks apply on this Mac while signed out." : "Blocks apply to your signed-in account.").foregroundStyle(.secondary)
                ForEach(account.blockedCreators.sorted(), id: \.self) { creator in
                    HStack {
                        Button("Creator " + String(creator.prefix(8))) { openCreator(creator) }.buttonStyle(.link)
                        Spacer()
                        Button("Unblock") { account.perform { try await account.setBlocked(creator, blocked: false) } }
                    }
                }
            }
            if account.accountID != nil {
                Button("Submit layout…") {
                    revising = nil; submitting = true
                }.disabled(layouts.isEmpty)
                ForEach(account.listings) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.title).font(.headline)
                        Text("Revision \(item.latest_revision) · \(item.status)" + (item.published_revision.map { " · Published revision \($0)" } ?? " · Not yet public")).foregroundStyle(.secondary)
                        if let review = account.reviews[item.id] {
                            Text("Review: " + review.review_status).font(.callout)
                            if let reason = review.review_reason, !reason.isEmpty { Text(reason).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                        HStack {
                            Button("Download a copy") { account.perform { importLayout(try await account.api.revision(item)); account.notice = "Downloaded revision \(item.latest_revision) to your layout library." } }.help("Download the newest submitted revision, including one awaiting review, as a new local copy.")
                            Button("Submit revision…") { revising = item; submitting = true }.disabled(layouts.isEmpty || item.status == "removed")
                            Button("Remove…", role: .destructive) { removing = item }.disabled(item.status == "removed")
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            DisclosureGroup("Server connection") {
                HStack { TextField("API base URL", text: $account.endpoint); Button("Apply") { account.setEndpoint() } }
                Text("Use the local development server until the public service is available.").font(.callout).foregroundStyle(.secondary)
            }
            if account.identity != nil {
                Divider()
                Button("Delete account…", role: .destructive) { deleting = true }
                    .foregroundStyle(.red)
            }
        }.disabled(account.busy)
        .sheet(isPresented: $submitting) {
            MarketplaceSubmissionView(account: account, layouts: layouts, screen: screen, revising: revising)
        }
        .sheet(isPresented: $account.deletionInProgress) {
            VStack(spacing: 18) {
                ProgressView()
                Text("Deleting account…").font(.title2.bold())
                Text("Please wait while we confirm deletion.").foregroundStyle(.secondary)
            }.padding(32).frame(width: 400).interactiveDismissDisabled()
        }
        .sheet(isPresented: $deleting) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Delete your account?").font(.title2.bold())
                Text("Your uploads will be **hidden immediately**. Your marketplace account, **all uploaded layouts**, reports, and account blocks will then be permanently deleted. **This cannot be undone.**")
                Text("**Local layouts stay on your devices.** Copies downloaded by other people remain, and you can keep using the controller without an account. Your local sign-in credentials will be cleared when the server accepts the request.")
                Text("You’ll **sign in again** to confirm the account. **Your Apple Account will not be deleted.** Afterward, remove this app from Sign in with Apple at account.apple.com; marketplace deletion does not automatically revoke Apple authorization.")
                HStack {
                    Button("Cancel") { deleting = false }
                    Spacer()
                    Button("Sign in and delete account", role: .destructive) { deleting = false; account.deleteAccount() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
            }.padding(24).frame(width: 480)
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

private struct MarketplaceSubmissionView: View {
    @ObservedObject var account: MarketplaceAccountModel
    let layouts: [LocalLayout]
    let screen: PhoneScreen?
    let revising: OwnedListing?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLayoutID = ""
    @State private var submissionLayout: LocalLayout?
    @State private var title = ""
    @State private var description = ""
    @State private var selectedGame: MarketplaceGame?
    @State private var selectedTags: Set<String> = []
    @State private var tags: [MarketplaceTag] = []
    @State private var loadingTags = false
    @State private var tagsError: String?
    @State private var choosingGame = false
    @State private var gameQuery = ""
    @State private var games: [MarketplaceGame] = []
    @State private var loadingGames = false
    @State private var gamesError: String?
    @State private var gamesRetry = 0
    @State private var submissionError: String?
    private var invalid: Bool {
        submissionLayout == nil || (revising == nil && (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 120 || description.count > 4000 || selectedTags.count > 10))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(revising == nil ? "Submit layout" : "Submit a new revision").font(.title2.bold())
            if let revising {
                Text(revising.title).foregroundStyle(.secondary)
                Text("This updates the controls only. The listing’s title, game, description, and tags stay the same.").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Layout", selection: $selectedLayoutID) {
                        Text("Choose a layout").tag("")
                        ForEach(layouts) { layout in
                            Text(layout.name + (layout.isPreset ? " · preset" : "") + (layouts.filter { $0.name == layout.name }.count > 1 ? " · " + String(layout.id.prefix(6)) : ""))
                                .tag(layout.id)
                        }
                    }.pickerStyle(.menu)
                    if let submissionLayout {
                        SubmissionLayoutPreview(layout: submissionLayout, screen: screen)
                    } else {
                        RoundedRectangle(cornerRadius: 18).fill(.quaternary.opacity(0.4))
                            .overlay { Label("Choose a layout to preview", systemImage: "gamecontroller").foregroundStyle(.secondary) }
                            .frame(height: 160)
                    }
                    if revising == nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Title").font(.headline)
                            TextField("Give your layout a name", text: $title)
                            if title.count > 120 { Text("Keep the title within 120 characters.").font(.caption).foregroundStyle(.red) }
                        }
                        gameChoice
                        tagChoices
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Intended use & description").font(.headline)
                            TextField("What is this layout useful for? Describe activities, key controls, and any setup needed.", text: $description, axis: .vertical).lineLimit(3...5)
                            if description.count > 4000 { Text("Keep the description within 4,000 characters.").font(.caption).foregroundStyle(.red) }
                        }
                    }
                    if let submissionLayout {
                        Text("A copy of “\(submissionLayout.name)” will be submitted for review.").font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(.trailing, 8)
            }.frame(maxHeight: 580)
            if let submissionError { Text(submissionError).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }.disabled(account.busy)
                Spacer()
                if account.busy { ProgressView().controlSize(.small) }
                if account.identity == nil { Button("Sign in again") { account.signIn() }.disabled(account.busy) }
                Button("Submit for review") { submit() }
                    .buttonStyle(PadActionStyle(prominent: !invalid))
                    .disabled(invalid || account.busy || account.identity == nil)
            }
        }.padding(24).frame(width: 640)
            .interactiveDismissDisabled(account.busy)
            .onChange(of: selectedLayoutID) { _, id in
                let previousName = submissionLayout?.name
                submissionLayout = layouts.first { $0.id == id }
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title == previousName { title = submissionLayout?.name ?? "" }
            }
            .onChange(of: layouts.map(\.id)) { _, ids in
                if !ids.contains(selectedLayoutID) { selectedLayoutID = ""; submissionLayout = nil }
            }
            .task { if revising == nil { await loadTags() } }
    }
    private var gameChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Game").font(.headline)
                Text("Optional").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(choosingGame ? "Done" : "Choose game…") { choosingGame.toggle() }
            }
            HStack {
                Text(selectedGame?.name ?? "General-purpose / no specific game")
                if selectedGame != nil { Button("Clear") { selectedGame = nil }.buttonStyle(.link) }
            }.foregroundStyle(.secondary)
            if choosingGame {
                TextField("Search games", text: $gameQuery)
                VStack(alignment: .leading, spacing: 8) {
                    if loadingGames { ProgressView().controlSize(.small) }
                    if let gamesError {
                        Text(gamesError).font(.callout).foregroundStyle(.secondary)
                        Button("Retry game search") { gamesRetry += 1 }
                    } else if !loadingGames && games.isEmpty {
                        Text(gameQuery.isEmpty ? "No games are available yet. You can submit a general-purpose layout." : "No matching games. Try another search, or leave the game unset.").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(games) { game in
                        Button { selectedGame = game; choosingGame = false } label: {
                            HStack {
                                Text(game.name)
                                Spacer()
                                if selectedGame?.id == game.id { Image(systemName: "checkmark") }
                            }.padding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.task(id: gameQuery + ":" + String(gamesRetry)) { await searchGames() }
            }
        }
    }
    private var tagChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Use-case tags").font(.headline)
                Text("Optional · \(selectedTags.count)/10").font(.caption).foregroundStyle(.secondary)
            }
            if loadingTags { ProgressView().controlSize(.small) }
            if let tagsError {
                Text(tagsError).font(.callout).foregroundStyle(.secondary)
                Button("Retry tags") { Task { await loadTags() } }
            } else if !loadingTags && tags.isEmpty {
                Text("No tags are available yet. You can submit without tags.").font(.callout).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(tags) { tag in
                    Toggle(tag.label, isOn: Binding(get: { selectedTags.contains(tag.slug) }, set: { selected in
                        if selected && selectedTags.count < 10 { selectedTags.insert(tag.slug) }
                        else if !selected { selectedTags.remove(tag.slug) }
                    })).toggleStyle(.checkbox)
                        .disabled(!selectedTags.contains(tag.slug) && selectedTags.count >= 10)
                }
            }
        }
    }
    private func searchGames() async {
        loadingGames = true; gamesError = nil; games = []
        do {
            try await Task.sleep(for: .milliseconds(250))
            let result = try await account.api.games(query: gameQuery)
            guard !Task.isCancelled else { return }
            games = result; loadingGames = false
        } catch {
            guard !Task.isCancelled else { return }
            gamesError = "Could not load games. Your current choice is unchanged. " + error.localizedDescription
            loadingGames = false
        }
    }
    private func loadTags() async {
        guard !loadingTags else { return }
        loadingTags = true; tagsError = nil
        defer { loadingTags = false }
        do { tags = try await account.api.tags() }
        catch { tagsError = "Could not load tags. You can retry or submit without them. " + error.localizedDescription }
    }
    private func submit() {
        guard let layout = submissionLayout else { return }
        let submittedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines), submittedDescription = description
        let gameID = selectedGame?.id, tagSlugs = selectedTags.sorted()
        submissionError = nil
        account.perform {
            let result: MarketplaceSubmission
            do {
                if let revising { result = try await account.api.revise(revising, document: layout.document) }
                else { result = try await account.api.submit(document: layout.document, title: submittedTitle, description: submittedDescription, gameID: gameID, tags: tagSlugs) }
            } catch { submissionError = error.localizedDescription; throw error }
            dismiss()
            let confirmation = "Revision \(result.revision) submitted for review."
            do { try await account.loadAccount(); account.notice = confirmation }
            catch { account.notice = confirmation + " Could not refresh My submissions: " + error.localizedDescription }
        }
    }
}
