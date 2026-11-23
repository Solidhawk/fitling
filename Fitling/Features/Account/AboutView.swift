import SwiftUI

/// Where the data, drawings and photos in the app come from (RISKS R-02, docs/BRONNEN.md).
struct AboutView: View {
    private var version: String? {
        guard let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        List {
            Section {
                source("account.about.off", url: "https://world.openfoodfacts.org")
                source("account.about.usda", url: "https://fdc.nal.usda.gov")
                source("account.about.prijsprofeet", url: "https://www.prijsprofeet.nl")
                source("account.about.everkinetic", url: "https://github.com/everkinetic/data")
                Text("account.about.photos")
            } header: {
                Text("account.about.sources")
            }
            .listRowBackground(Color.card)
            if let version {
                Section {
                    Text("account.about.version \(version)").foregroundStyle(Color.inkSoft)
                }
                .listRowBackground(Color.card)
            }
        }
        .groundBackground()
        .navigationTitle("account.about")
    }

    private func source(_ key: LocalizedStringKey, url: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(key)
            if let link = URL(string: url) {
                Link(destination: link) {
                    // A line of footnote is far below the 44 pt a finger needs.
                    Text(verbatim: link.host() ?? url).font(.footnote)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
        }
    }
}
