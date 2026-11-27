import Foundation
import Testing

/// The app shows its own icon (UNFORGET S37): the AppIcon set of the asset catalog, named in project.yml.
@Suite struct AppIconTests {
    @Test func theAppNamesItsIcon() throws {
        let icons = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any], "no CFBundleIcons")
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any], "no CFBundlePrimaryIcon")
        #expect(primary["CFBundleIconName"] as? String == "AppIcon")
    }
}
