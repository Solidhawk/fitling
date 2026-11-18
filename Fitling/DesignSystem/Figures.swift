import SwiftUI

/// The four species from PRODUCT.md.
enum Species: CaseIterable, Identifiable {
    case sprout, ember, pip, pebble

    var id: Self { self }
}

/// One flat part of a figure, drawn in a 100 × 100 space.
struct FigurePart {
    enum Paint: Equatable {
        case fill
        case stroke(CGFloat)
        case fillAndStroke(CGFloat)
    }

    static let baseline: CGFloat = 92
    static let keylineWidth: CGFloat = 7

    let path: Path
    let color: Color
    var paint: Paint = .fill
    var keyline = false
}

extension Species {
    var parts: [FigurePart] { [] }
}
