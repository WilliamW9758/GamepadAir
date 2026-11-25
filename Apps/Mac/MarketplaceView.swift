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
    @State private var notice: String?
    @State private var selectedExample: Example?
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
    private var results: [PublicListing] { listings.filter { matches($0.title, $0.description, inputCategory($0)) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if showingSubmissions {
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
                    if loading { ProgressView().controlSize(.small) }
                    Text(query.isEmpty ? "Explore layouts" : "Search results").font(.title2.bold())
                    if !listings.isEmpty && results.isEmpty && !loading { ContentUnavailableView.search(text: query) }
                    if listings.isEmpty && !loading {
                        Text("Community layouts are on their way. These examples show what you can create; they aren’t downloads.").foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 20)], spacing: 20) {
                        ForEach(results) { item in
                            VStack(alignment: .leading, spacing: 14) {
                                Group {
                                    if let preview = previews[previewKey(item)] { MarketplaceLayoutThumbnail(document: preview.document) }
                                    else { RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.08)).overlay { Text(loading ? "Loading preview…" : "Preview unavailable").font(.callout).foregroundStyle(.secondary) } }
                                }.frame(height: 140)
                                Text(item.title).font(.headline)
                                Text(item.description).foregroundStyle(.secondary)
                                HStack {
                                    Text(inputCategory(item)).foregroundStyle(.secondary)
                                    Spacer()
                                    Button(isSaved(item) ? "Saved" : "Get layout") {
                                        guard let layout = previews[previewKey(item)] else { return }
                                        if model.importMarketplaceDocument(layout.document, provenance: layout.provenance) { notice = nil }
                                        else { notice = model.profileNotice }
                                    }.disabled(isSaved(item) || previews[previewKey(item)] == nil)
                                }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                        }
                        if listings.isEmpty && !loading {
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
    private func artwork(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity).frame(height: 120)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
    private func browse() async {
        guard !loading else { return }; loading = true
        defer { loading = false }
        do {
            let client = try account.api
            listings = try await client.browse(); notice = nil
            let validKeys = Set(listings.map(previewKey))
            previews = previews.filter { validKeys.contains($0.key) }
            for listing in listings where previews[previewKey(listing)] == nil {
                guard !Task.isCancelled else { return }
                if let layout = try? await client.download(listing) { previews[previewKey(listing)] = layout }
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
                            if control.role == "dpad", mode?.dpadStyle == "fourWay" {
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
                        }.frame(width: diameter, height: diameter)
                            .position(x: control.placement.x * width * scale, y: control.placement.y * height * scale)
                    }
                }.frame(width: width * scale, height: height * scale)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("Layout preview: \(document.name)")
    }
}
