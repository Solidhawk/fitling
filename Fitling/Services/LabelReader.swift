import CoreGraphics
import FitlingCore
import ImageIO
import Vision

/// Reads the nutrition table on a photo of a package with Vision, on the iPhone itself: the photo leaves the device
/// only if the user shares the product later (ARCHITECTURE §5, step 3).
enum LabelReader {
    /// The languages of the labels in the shops the app is for, as far as this iPhone's Vision knows them. Dutch words
    /// are read with the other Latin languages when Vision has no Dutch.
    private static let languages = ["nl-NL", "de-DE", "fr-FR", "en-GB", "en-US"]
    /// Plenty for the small print of a table, and a 48-megapixel photo is not decoded whole.
    private static let longestSide = 3000

    /// What the photo says; nil when it cannot be opened. Slow on a large photo: call it away from the main actor.
    static func read(_ photo: Data) -> NutritionLabel? {
        guard let picture = upright(photo) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // The words of a label are no sentences, and its numbers must stay as printed.
        request.usesLanguageCorrection = false
        if let supported = try? request.supportedRecognitionLanguages() {
            let wanted = languages.filter(supported.contains)
            if !wanted.isEmpty { request.recognitionLanguages = wanted }
        }
        do {
            try VNImageRequestHandler(cgImage: picture, orientation: .up).perform([request])
        } catch {
            return nil
        }
        let pieces = (request.results ?? []).compactMap { observation -> NutritionLabel.Piece? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // A longer piece of a tilted photo gets a tilted box with the slope of the photo, a short one an upright
            // box: slope 0, which NutritionLabel.rows reads as unknown. The boxes of its words are no better.
            return piece(
                candidate.string, topLeft: observation.topLeft, topRight: observation.topRight,
                bottomLeft: observation.bottomLeft, bottomRight: observation.bottomRight
            )
        }
        return NutritionLabel.read(NutritionLabel.rows(pieces))
    }

    /// The photo the right way up and at most `longestSide` pixels: ImageIO applies the orientation the camera wrote.
    private static func upright(_ photo: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(photo as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A piece from the four corners Vision gives, measured from the bottom left: its middle from the top, its height
    /// along its own side (the box around a tilted line is far taller than the line), and the slope of its baseline
    /// as down per width.
    static func piece(_ text: String, topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) -> NutritionLabel.Piece {
        let middleX = Double(topLeft.x + topRight.x + bottomLeft.x + bottomRight.x) / 4
        let middleY = Double(topLeft.y + topRight.y + bottomLeft.y + bottomRight.y) / 4
        let height = Double(hypot(topLeft.x - bottomLeft.x, topLeft.y - bottomLeft.y))
        let width = Double(topRight.x - topLeft.x)
        let slope = width > 0 ? -Double(topRight.y - topLeft.y) / width : 0
        return NutritionLabel.Piece(text: text, x: middleX, y: 1 - middleY, height: height, slope: slope)
    }
}
