import SwiftUI

/// The package photo from the product source, or, without one, the product's first letter on
/// a track-coloured tile. Never a generated picture of food.
struct ProductThumbnail: View {
    let imageURL: String?
    let name: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let url = imageURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size / 4, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color.track
            Text(verbatim: Self.initial(of: name))
                .font(.system(size: size * 0.45, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)
        }
    }

    /// The first letter or digit of the name, upper case; a dash when there is none.
    nonisolated static func initial(of name: String) -> String {
        name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "–"
    }
}

enum ImageCache {
    /// Package photos are kept on disk, so a product logged every day is not fetched every day.
    static func configure() {
        URLCache.shared = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 150 * 1024 * 1024)
    }
}
