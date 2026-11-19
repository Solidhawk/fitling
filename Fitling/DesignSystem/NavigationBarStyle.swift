import SwiftUI
import UIKit

/// Navigation bars on the opaque ground with rounded titles, so a bar is part of the page and
/// never a frosted layer. Title sizes follow the text size at launch.
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
        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
        bar.scrollEdgeAppearance = appearance
    }

    /// `traits` nil means the text size the app runs with.
    static func inlineTitleFont(traits: UITraitCollection?) -> UIFont {
        rounded(.headline, weight: .bold, maximumSize: .greatestFiniteMagnitude, traits: traits)
    }

    static func largeTitleFont(traits: UITraitCollection?) -> UIFont {
        rounded(.largeTitle, weight: .heavy, maximumSize: .greatestFiniteMagnitude, traits: traits)
    }

    private static func rounded(_ style: UIFont.TextStyle, weight: UIFont.Weight, maximumSize: CGFloat, traits: UITraitCollection?) -> UIFont {
        let size = min(UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize, maximumSize)
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(.rounded) else { return system }
        return UIFont(descriptor: descriptor, size: size)
    }
}
