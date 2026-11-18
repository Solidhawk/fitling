import SwiftUI
import UIKit

/// Navigation bars on the opaque ground with rounded titles, so a bar is part of the page and
/// never a frosted layer. Title sizes follow the text size at launch.
@MainActor
enum NavigationBarStyle {
    static func apply() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(resource: .ground)
        appearance.shadowColor = .clear
        let ink = UIColor(resource: .ink)
        appearance.titleTextAttributes = [.font: rounded(.headline, weight: .bold), .foregroundColor: ink]
        appearance.largeTitleTextAttributes = [.font: rounded(.largeTitle, weight: .heavy), .foregroundColor: ink]

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
        bar.scrollEdgeAppearance = appearance
    }

    private static func rounded(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(.rounded) else { return system }
        return UIFont(descriptor: descriptor, size: size)
    }
}
