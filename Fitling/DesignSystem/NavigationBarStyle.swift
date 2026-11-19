import SwiftUI
import UIKit

/// Navigation bars on the opaque ground with rounded titles, so a bar is part of the page and
/// never a frosted layer. Title sizes follow the text size at launch, up to a maximum: a bar has a
/// fixed height, and a title that keeps growing is cut off.
@MainActor
enum NavigationBarStyle {
    static let inlineTitleMaximum: CGFloat = 22
    static let largeTitleMaximum: CGFloat = 40

    static func apply() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(resource: .ground)
        appearance.shadowColor = .clear
        let ink = UIColor(resource: .ink)
        appearance.titleTextAttributes = [.font: inlineTitleFont(traits: nil), .foregroundColor: ink]
        appearance.largeTitleTextAttributes = [.font: largeTitleFont(traits: nil), .foregroundColor: ink]

        let bar = UINavigationBar.appearance()
        // The back button is drawn by UIKit and does not see the SwiftUI tint.
        bar.tintColor = ink
        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
        bar.scrollEdgeAppearance = appearance

        // The tab bar on the same opaque ground, so the page does not end in a frosted strip.
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(resource: .ground)
        tabs.shadowColor = UIColor(resource: .track)
        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tabs
        tabBar.scrollEdgeAppearance = tabs
    }

    /// `traits` nil means the text size the app runs with.
    static func inlineTitleFont(traits: UITraitCollection?) -> UIFont {
        rounded(.headline, weight: .bold, maximumSize: inlineTitleMaximum, traits: traits)
    }

    static func largeTitleFont(traits: UITraitCollection?) -> UIFont {
        rounded(.largeTitle, weight: .heavy, maximumSize: largeTitleMaximum, traits: traits)
    }

    private static func rounded(_ style: UIFont.TextStyle, weight: UIFont.Weight, maximumSize: CGFloat, traits: UITraitCollection?) -> UIFont {
        let size = min(UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize, maximumSize)
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(.rounded) else { return system }
        return UIFont(descriptor: descriptor, size: size)
    }
}
