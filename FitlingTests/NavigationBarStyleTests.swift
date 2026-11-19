import Testing
import UIKit
@testable import Fitling

/// A navigation bar has a fixed height. A title that grows with the largest text sizes is cut
/// off ("Jouw gegeve…" in the first Verzamelfiguren screenshots), so titles stop growing at a
/// maximum; the content below the bar still scales fully.
@MainActor
@Suite struct NavigationBarStyleTests {
    let standard = UITraitCollection(preferredContentSizeCategory: .large)
    let largest = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)

    @Test func titlesFollowTheStandardTextSize() {
        #expect(NavigationBarStyle.inlineTitleFont(traits: standard).pointSize == 17)
        #expect(NavigationBarStyle.largeTitleFont(traits: standard).pointSize == 34)
    }

    @Test func titlesStopGrowingAtTheLargestTextSize() {
        #expect(NavigationBarStyle.inlineTitleFont(traits: largest).pointSize == NavigationBarStyle.inlineTitleMaximum)
        #expect(NavigationBarStyle.largeTitleFont(traits: largest).pointSize == NavigationBarStyle.largeTitleMaximum)
    }
}
