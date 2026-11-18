import CoreGraphics

/// The 4-pt spacing scale.
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Corner radii. Everything in the catalog is rounded, with continuous corners.
enum Radius {
    static let card: CGFloat = 24
    /// Half the minimum ribbon height, so a one-line ribbon is a capsule.
    static let ribbon: CGFloat = 22
}

/// Shared button height: the system Apple button and our own capsules line up.
enum ButtonMetrics {
    static let height: CGFloat = 54
}
