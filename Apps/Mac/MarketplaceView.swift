import SwiftUI

/// Local, explicitly marked preview; no network or account is needed.
struct MarketplaceView: View {
    @State private var query = ""
    @State private var category = "All"
    @State private var selected: Example?
    private struct Example: Identifiable {
        let id: String, subtitle: String, category: String, symbol: String
    }
    private let examples = [
        Example(id: "Adventure essentials", subtitle: "Movement, camera and quick actions", category: "Games", symbol: "mountain.2"),
        Example(id: "Driving controls", subtitle: "Steering, acceleration and braking", category: "Games", symbol: "car"),
        Example(id: "Desktop companion", subtitle: "Trackpad and everyday shortcuts", category: "Desktop", symbol: "desktopcomputer"),
        Example(id: "Presentation remote", subtitle: "Slides, pointer and playback", category: "Desktop", symbol: "play.rectangle")
    ]
    private var results: [Example] {
        examples.filter { (category == "All" || $0.category == category) && (query.isEmpty || ($0.id + " " + $0.subtitle).localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search example layouts", text: $query).textFieldStyle(.plain)
                }.padding(12).background(.quaternary, in: Capsule())
                HStack {
                    ForEach(["All", "Games", "Desktop"], id: \.self) { item in
                        Button(item) { category = item }.buttonStyle(PadActionStyle(prominent: item == category))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Find your next layout.").font(.largeTitle.bold())
                    Text("Marketplace preview").font(.headline).foregroundStyle(Color.accentColor)
                    Text("Browse example designs below. Community search, sharing and downloads are coming later.")
                        .foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                Text(query.isEmpty ? "Explore layouts" : "Search results").font(.title2.bold())
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 20)], spacing: 20) {
                    ForEach(results) { item in
                        Button { selected = item } label: {
                            VStack(alignment: .leading, spacing: 14) {
                                Image(systemName: item.symbol).font(.system(size: 44)).foregroundStyle(Color.accentColor)
                                    .frame(maxWidth: .infinity).frame(height: 120)
                                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                                Text(item.id).font(.headline)
                                Text(item.subtitle).foregroundStyle(.secondary)
                                HStack { Text(item.category); Spacer(); Text("Preview").foregroundStyle(Color.accentColor) }
                            }.font(.system(size: 14)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(24)
        }.sheet(item: $selected) { item in
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: item.symbol).font(.largeTitle).foregroundStyle(Color.accentColor)
                Text(item.id).font(.title2.bold())
                Text(item.subtitle)
                Text("This is an example listing, not a downloadable layout. Community layouts will appear here when the marketplace launches.").foregroundStyle(.secondary)
                HStack { Button("Downloads coming later") {}.disabled(true); Spacer(); Button("Done") { selected = nil } }
            }.padding(28).frame(width: 460).buttonStyle(PadActionStyle())
        }
    }
}
