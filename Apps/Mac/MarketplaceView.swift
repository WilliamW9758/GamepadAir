import SwiftUI

struct MarketplaceView: View {
    @ObservedObject var model: HostModel
    @StateObject private var account = MarketplaceAccountModel()
    @State private var query = ""
    @State private var category = "All"
    @State private var listings: [PublicListing] = []
    @State private var loading = false
    @State private var notice: String?
    private var results: [PublicListing] {
        listings.filter { (category == "All" || $0.input_type == category) && (query.isEmpty || ($0.title + " " + $0.description).localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MarketplaceAccountView(account: account, currentLayout: model.update.layout?.layout ?? model.portable) { document in model.importMarketplaceDocument(document) }
                Divider()
                HStack {
                    Text("Community layouts").font(.largeTitle.bold())
                    Spacer()
                    Button("Refresh") { Task { await browse() } }.disabled(loading)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter loaded layouts", text: $query).textFieldStyle(.plain)
                }.padding(12).background(.quaternary, in: Capsule())
                Picker("Input type", selection: $category) {
                    Text("All").tag("All"); Text("Keyboard & mouse").tag("keyboardMouse"); Text("Controller").tag("gamepad")
                }.pickerStyle(.segmented)
                if loading { ProgressView() }
                if let notice { Text(notice).foregroundStyle(.secondary) }
                if results.isEmpty && !loading { Text("No published layouts to show.").foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 20)], spacing: 20) {
                    ForEach(results) { item in
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: item.input_type == "gamepad" ? "gamecontroller" : "keyboard").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                            Text(item.title).font(.headline)
                            Text(item.description).foregroundStyle(.secondary)
                            Button("Get layout") { Task {
                                do { let layout = try await account.api.download(item); model.importMarketplaceDocument(layout.document, provenance: layout.provenance); notice = model.profileNotice }
                                catch { notice = error.localizedDescription }
                            } }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }.padding(24)
        }.task { account.restore(); await browse() }
    }
    private func browse() async {
        guard !loading else { return }; loading = true; notice = nil
        defer { loading = false }
        do { listings = try await account.api.browse() }
        catch { notice = "Could not load community layouts: " + error.localizedDescription }
    }
}
