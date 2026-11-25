import SwiftUI

struct MarketplaceView: View {
    @ObservedObject var model: HostModel
    @StateObject private var account = MarketplaceAccountModel()
    @State private var showingSubmissions = false
    @State private var query = ""
    @State private var category = "All"
    @State private var listings: [PublicListing] = []
    @State private var loading = false
    @State private var notice: String?
    @State private var selectedExample: Example?
    private struct Example: Identifiable {
        let id: String, subtitle: String, category: String, symbol: String
    }
    private let examples = [
        Example(id: "Adventure essentials", subtitle: "Movement, camera and quick actions", category: "Controller", symbol: "mountain.2"),
        Example(id: "Driving controls", subtitle: "Steering, acceleration and braking", category: "Controller", symbol: "car"),
        Example(id: "Desktop companion", subtitle: "Trackpad and everyday shortcuts", category: "Keyboard & mouse", symbol: "desktopcomputer"),
        Example(id: "Presentation remote", subtitle: "Slides, pointer and playback", category: "Keyboard & mouse", symbol: "play.rectangle")
    ]
    private func matches(_ title: String, _ detail: String, _ type: String) -> Bool {
        (category == "All" || category == type) && (query.isEmpty || (title + " " + detail).localizedCaseInsensitiveContains(query))
    }
    private var results: [PublicListing] { listings.filter { matches($0.title, $0.description, $0.input_type == "gamepad" ? "Controller" : "Keyboard & mouse") } }
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
                        ForEach(["All", "Controller", "Keyboard & mouse"], id: \.self) { item in
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
                    if loading && listings.isEmpty { ProgressView() }
                    Text(query.isEmpty ? "Explore layouts" : "Search results").font(.title2.bold())
                    if !listings.isEmpty && results.isEmpty { ContentUnavailableView.search(text: query) }
                    if listings.isEmpty && !loading {
                        Text("Community layouts are on their way. These examples show what you can create; they aren’t downloads.").foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 20)], spacing: 20) {
                        ForEach(results) { item in
                            VStack(alignment: .leading, spacing: 14) {
                                artwork(item.input_type == "gamepad" ? "gamecontroller" : "keyboard")
                                Text(item.title).font(.headline)
                                Text(item.description).foregroundStyle(.secondary)
                                HStack {
                                    Text(item.input_type == "gamepad" ? "Controller" : "Keyboard & mouse").foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Get layout") { Task {
                                        do { let layout = try await account.api.download(item); model.importMarketplaceDocument(layout.document, provenance: layout.provenance); notice = model.profileNotice }
                                        catch { notice = error.localizedDescription }
                                    } }
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
        do { listings = try await account.api.browse(); notice = nil }
        catch { notice = "Could not load community layouts: " + error.localizedDescription }
    }
}
