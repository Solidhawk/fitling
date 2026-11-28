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
                source("account.about.off", name: "Open Food Facts", url: "https://world.openfoodfacts.org")
                // The terms of NEVO ask for the source and version as written in account.about.nevo (UNFORGET S15).
                source("account.about.nevo", name: "NEVO-online", url: "https://nevo-online.rivm.nl")
                source("account.about.usda", name: "USDA FoodData Central", url: "https://fdc.nal.usda.gov")
                source("account.about.prijsprofeet", name: "PrijsProfeet", url: "https://www.prijsprofeet.nl")
                source("account.about.everkinetic", name: "Everkinetic", url: "https://github.com/everkinetic/data")
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
        // Ink like every other list: the system grey of the section header is too faint on the pastel ground.
        .foregroundStyle(Color.ink)
        .groundBackground()
        .navigationTitle("account.about")
    }

    /// `name` is the source's own name, the same in every language.
    private func source(_ key: LocalizedStringKey, name: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(key)
            if let link = URL(string: url) {
                Link(destination: link) {
                    // A line of footnote is far below the 44 pt a finger needs.
                    Text(verbatim: link.host() ?? url).font(.footnote)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                // VoiceOver would spell out the web address.
                .accessibilityLabel(Text("account.about.website \(name)"))
            }
        }
    }
}
