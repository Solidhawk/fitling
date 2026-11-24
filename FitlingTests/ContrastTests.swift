import Testing
import UIKit
@testable import Fitling

/// Text against its ground, in light and in dark: at least WCAG AA (4.5:1) for normal text (TASKS 7.2).
@MainActor
@Suite struct ContrastTests {
    static func ratio(_ foreground: ColorResource, _ background: ColorResource, _ style: UIUserInterfaceStyle) -> Double {
        let traits = UITraitCollection(userInterfaceStyle: style)
        func luminance(_ resource: ColorResource) -> Double {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            UIColor(resource: resource).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            func linear(_ value: CGFloat) -> Double {
                let v = Double(value)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func theDateOnAProgressPhotoIsReadable(_ style: UIUserInterfaceStyle) {
        #expect(Self.ratio(PhotoDateChip.foreground, PhotoDateChip.background, style) >= 4.5)
    }
}
