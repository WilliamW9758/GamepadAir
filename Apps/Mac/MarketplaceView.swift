import SwiftUI

struct MarketplaceView: View {
    @ObservedObject var model: HostModel
    @StateObject private var account = MarketplaceAccountModel()
    @State private var showingSubmissions = false
    @State private var query = ""
    @State private var category = "All"
    @State private var listings: [PublicListing] = []
    @State private var previews: [String: LocalLayout] = [:]
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var notice: String?
    @State private var selectedExample: Example?
    @State private var selectedListing: PublicListing?
    @State private var reporting: PublicListing?
    @State private var blocking: PublicListing?
    @State private var reportReason = MarketplaceReportReason.abuse
    @State private var reportExplanation = ""
    @State private var reportError: String?
    @State private var reportingBusy = false
    private struct Example: Identifiable {
        let id: String, subtitle: String, category: String, symbol: String
    }
    private let examples = [
        Example(id: "Adventure essentials", subtitle: "Movement, camera and quick actions", category: "Xbox", symbol: "mountain.2"),
        Example(id: "Driving controls", subtitle: "Steering, acceleration and braking", category: "PlayStation", symbol: "car"),
        Example(id: "Desktop companion", subtitle: "Trackpad and everyday shortcuts", category: "Keyboard & mouse", symbol: "desktopcomputer"),
        Example(id: "Presentation remote", subtitle: "Slides, pointer and playback", category: "Keyboard & mouse", symbol: "play.rectangle")
    ]
    private func matches(_ title: String, _ detail: String, _ type: String) -> Bool {
        (category == "All" || category == type) && (query.isEmpty || (title + " " + detail).localizedCaseInsensitiveContains(query))
    }
    private func previewKey(_ listing: PublicListing) -> String { listing.id + ":" + String(listing.current_revision.number) + ":" + listing.current_revision.digest }
    private func inputCategory(_ listing: PublicListing) -> String {
        guard listing.input_type == "gamepad" else { return "Keyboard & mouse" }
        guard let layout = previews[previewKey(listing)] else { return "Controller" }
        return layout.effectiveControllerStyle == .xbox ? "Xbox" : "PlayStation"
    }
    private func isSaved(_ listing: PublicListing) -> Bool {
        model.localLayouts.contains { $0.provenance?.publicationID == listing.id && $0.provenance?.revisionID == String(listing.current_revision.number) && $0.provenance?.digest == listing.current_revision.digest }
    }
    private var results: [PublicListing] { listings.filter { !account.blockedCreators.contains($0.creator_id ?? "") && matches($0.title, $0.description, inputCategory($0)) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let item = selectedListing {
                    Button { selectedListing = nil } label: { Label("Back to Marketplace", systemImage: "chevron.left") }
                    HStack {
                        Text(item.title).font(.largeTitle.bold())
                        Spacer()
                        Button(isSaved(item) ? "Saved" : "Get layout") { save(item) }.disabled(isSaved(item) || previews[previewKey(item)] == nil)
                    }
                    Text(item.description).foregroundStyle(.secondary)
                    Text(inputCategory(item)).font(.headline)
                    HStack {
                        Button("Report layout…") { reportReason = .abuse; reportExplanation = ""; reportError = nil; reporting = item }
                        if let creator = item.creator_id, creator != account.accountID {
                            Button("Block creator…") { blocking = item }.disabled(account.busy)
                        }
                    }
                    if let preview = previews[previewKey(item)] {
                        SubmissionLayoutPreview(layout: preview, screen: model.update.connected ? model.libraryScreen : nil)
                        if model.update.connected, let screen = model.libraryScreen {
                            Text("Preview for your iPhone · \(Int(screen.width)) × \(Int(screen.height)) pt").font(.callout).foregroundStyle(.secondary)
                        }
                    } else { Text("Preview unavailable").foregroundStyle(.secondary) }
                    if let notice { Text(notice).foregroundStyle(.secondary) }
                } else if showingSubmissions {
                    Button { showingSubmissions = false } label: { Label("Back to Marketplace", systemImage: "chevron.left") }
                    MarketplaceAccountView(account: account, layouts: model.localLayouts, screen: model.libraryScreen) { document in model.importMarketplaceDocument(document) }
                } else {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search layouts", text: $query).textFieldStyle(.plain)
                    }.padding(12).background(.quaternary, in: Capsule())
                    HStack {
                        ForEach(["All", "Xbox", "PlayStation", "Keyboard & mouse"], id: \.self) { item in
                            Button(item) { category = item }.buttonStyle(PadActionStyle(prominent: item == category))
                        }
                        Spacer()
                        Button("My submissions") { showingSubmissions = true }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Find your next layout.").font(.largeTitle.bold())
                        Text("Made for the way you play").font(.headline).foregroundStyle(Color.accentColor)
                        Text("Discover community controls for your games and everyday apps. Make any layout your own.").foregroundStyle(.secondary)
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    if let notice { Text(notice).foregroundStyle(.secondary) }
                    Text(query.isEmpty ? "Explore layouts" : "Search results").font(.title2.bold())
                    if !listings.isEmpty && results.isEmpty && !loading { ContentUnavailableView.search(text: query) }
                    if listings.isEmpty && !loading && hasLoaded {
                        Text("Community layouts are on their way. These examples show what you can create; they aren’t downloads.").foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 20)], spacing: 20) {
                        if listings.isEmpty && (loading || !hasLoaded) {
                            ForEach(0..<4, id: \.self) { _ in MarketplaceSkeletonCard() }
                        }
                        ForEach(results) { item in
                            VStack(alignment: .leading, spacing: 14) {
                                Button { selectedListing = item } label: { VStack(alignment: .leading, spacing: 14) {
                                Group {
                                    if let preview = previews[previewKey(item)] { MarketplaceLayoutThumbnail(document: preview.document) }
                                    else if loading { MarketplaceSkeletonBlock().accessibilityLabel("Loading layout preview") }
                                    else { RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.08)).overlay { Text("Preview unavailable").font(.callout).foregroundStyle(.secondary) } }
                                }.frame(height: 140)
                                Text(item.title).font(.headline)
                                Text(item.description).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain)
                                HStack {
                                    Text(inputCategory(item)).foregroundStyle(.secondary)
                                    Spacer()
                                    Button(isSaved(item) ? "Saved" : "Get layout") {
                                        save(item)
                                    }.disabled(isSaved(item) || previews[previewKey(item)] == nil)
                                }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                        }
                        if listings.isEmpty && !loading && hasLoaded {
                            ForEach(examples.filter { matches($0.id, $0.subtitle, $0.category) }) { item in
                                Button { selectedExample = item } label: {
                                    VStack(alignment: .leading, spacing: 14) {
                                        artwork(item.symbol)
                                        Text(item.id).font(.headline)
                                        Text(item.subtitle).foregroundStyle(.secondary)
                                        HStack { Text(item.category); Spacer(); Text("Preview").foregroundStyle(Color.accentColor) }
                                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.padding(24)
        }
        .task {
            account.restore(); await browse()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                if showingSubmissions { await account.updateInBackground() } else { await browse() }
            }
        }
        .onChange(of: showingSubmissions) { _, showing in Task { if showing { await account.updateInBackground() } else { await browse() } } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { if showingSubmissions { await account.updateInBackground() } else { await browse() } }
        }
        .onChange(of: account.catalogVersion) { _, _ in
            selectedListing = nil; previews = [:]; listings = []
            Task { await browse() }
        }
        .sheet(item: $reporting) { item in
            VStack(alignment: .leading, spacing: 16) {
                Text("Report “\(item.title)”").font(.title2.bold())
                Picker("Reason", selection: $reportReason) {
                    ForEach(MarketplaceReportReason.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Explanation (optional)", text: $reportExplanation, axis: .vertical).lineLimit(3...6)
                Text("\(reportExplanation.count) / 2,000 characters").font(.caption).foregroundStyle(.secondary)
                Text("Your report will be reviewed. Reporting does not automatically remove a layout.").font(.callout).foregroundStyle(.secondary)
                if let reportError { Text(reportError).foregroundStyle(.red) }
                if reportingBusy { ProgressView().controlSize(.small) }
                HStack {
                    Button("Cancel") { reporting = nil }.disabled(reportingBusy)
                    Spacer()
                    Button("Send report") {
                        reportingBusy = true; reportError = nil
                        Task {
                            defer { reportingBusy = false }
                            do {
                                try await account.api.report(item, reason: reportReason, explanation: reportExplanation)
                                reporting = nil; notice = "Report received. Thank you."
                            } catch { reportError = error.localizedDescription }
                        }
                    }.disabled(reportingBusy || reportExplanation.count > 2000)
                }
            }.padding(24).frame(width: 480).interactiveDismissDisabled(reportingBusy)
        }
        .confirmationDialog("Block this creator?", isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } })) {
            if let creator = blocking?.creator_id {
                Button("Block creator") {
                    blocking = nil
                    account.perform {
                        do { try await account.setBlocked(creator, blocked: true); notice = "Creator blocked." }
                        catch { notice = error.localizedDescription; throw error }
                    }
                }
            }
        } message: { Text("Their layouts will be hidden. Downloaded copies remain. Manage blocks in My submissions." + (account.identity == nil ? " This block stays on this Mac while signed out." : "")) }
        .sheet(item: $selectedExample) { item in
            VStack(alignment: .leading, spacing: 20) {
                artwork(item.symbol)
                Text(item.id).font(.title2.bold())
                Text(item.subtitle)
                Text("This is an example design, not a published layout. Create your own in Layout & mappings.").foregroundStyle(.secondary)
                HStack { Spacer(); Button("Done") { selectedExample = nil } }
            }.padding(24).frame(width: 440)
        }
    }
    private func save(_ item: PublicListing) {
        let version = account.catalogVersion
        Task {
            do {
                let layout = try await account.api.download(item)
                guard account.catalogVersion == version, !account.blockedCreators.contains(item.creator_id ?? "") else { return }
                if model.importMarketplaceDocument(layout.document, provenance: layout.provenance) { notice = nil }
                else { notice = model.profileNotice }
            } catch { notice = error.localizedDescription }
        }
    }
    private func artwork(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity).frame(height: 120)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
    private func browse() async {
        guard !loading else { return }; loading = true
        let version = account.catalogVersion
        defer {
            loading = false; hasLoaded = true
            if version != account.catalogVersion { Task { await browse() } }
        }
        do {
            let client = try account.api
            let loaded = try await client.browse()
            guard version == account.catalogVersion else { return }
            listings = loaded.filter { !account.blockedCreators.contains($0.creator_id ?? "") }
            if let selectedListing, !listings.contains(where: { $0.id == selectedListing.id }) { self.selectedListing = nil }
            let validKeys = Set(listings.map(previewKey))
            previews = previews.filter { validKeys.contains($0.key) }
            for listing in listings where previews[previewKey(listing)] == nil {
                guard !Task.isCancelled else { return }
                if let layout = try? await client.download(listing) {
                    guard version == account.catalogVersion else { return }
                    previews[previewKey(listing)] = layout
                }
            }
        }
        catch { notice = "Could not load community layouts: " + error.localizedDescription }
    }
}

/// Simplified overview using the same control geometry as the phone and editor.
private struct MarketplaceLayoutThumbnail: View {
    let document: LayoutDocument
    var body: some View {
        GeometryReader { geometry in
            let width = 912.0, height = 420.0
            let scale = max(0.01, min((geometry.size.width - 20) / width, (geometry.size.height - 20) / height))
            let mode = document.modes.first { $0.id == document.initialMode }
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.08))
                ZStack {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                    ForEach(LayoutGeometry.resolve(document, modeID: document.initialMode, width: width, height: height).filter { !$0.hidden }) { control in
                        let diameter = control.radius * 2 * scale
                        ZStack {
                            if control.rectangular {
                                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15))
                                RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
                            } else if control.role == "dpad", mode?.dpadStyle == "fourWay" {
                                DPadCross().fill(Color.accentColor.opacity(0.25))
                                DPadCross().stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
                            } else {
                                Circle().fill(Color.accentColor.opacity(0.12))
                                Circle().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                            }
                            if ["leftStick", "rightStick"].contains(control.role) {
                                Circle().fill(Color.accentColor.opacity(0.6)).frame(width: diameter * 0.32, height: diameter * 0.32)
                            } else if diameter >= 22 {
                                Text(control.role == "dpad" ? "✣" : control.label).font(.system(size: 10, weight: .semibold)).lineLimit(1).foregroundStyle(Color.primary.opacity(0.8))
                            }
                        }.frame(width: control.width * scale, height: control.height * scale)
                            .position(x: control.placement.x * width * scale, y: control.placement.y * height * scale)
                    }
                }.frame(width: width * scale, height: height * scale)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("Layout preview: \(document.name)")
    }
}

private struct MarketplaceSkeletonBlock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.primary.opacity(pulse ? 0.10 : 0.05))
            .onAppear { if !reduceMotion { pulse = true } }
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
    }
}

private struct MarketplaceSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MarketplaceSkeletonBlock().frame(height: 140)
            MarketplaceSkeletonBlock().frame(width: 160, height: 20)
            MarketplaceSkeletonBlock().frame(height: 16)
            MarketplaceSkeletonBlock().frame(height: 16).padding(.trailing, 40)
            HStack {
                MarketplaceSkeletonBlock().frame(width: 90, height: 16)
                Spacer()
                MarketplaceSkeletonBlock().frame(width: 110, height: 40)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .ignore).accessibilityLabel("Loading layout")
            .allowsHitTesting(false)
    }
}
