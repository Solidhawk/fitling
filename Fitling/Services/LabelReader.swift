import FitlingCore
import ImageIO
import UIKit
import Vision

/// Reads the nutrition table on a photo of a package with Vision, on the iPhone itself: the photo leaves the device
/// only if the user shares the product later (ARCHITECTURE §5, step 3).
enum LabelReader {
    /// The languages of the labels in the shops the app is for, as far as this iPhone's Vision knows them. Dutch words
    /// are read with the other Latin languages when Vision has no Dutch.
    private static let languages = ["nl-NL", "de-DE", "fr-FR", "en-GB", "en-US"]

    /// What the photo says; nil when it cannot be read at all. Slow on a large photo: call it away from the main actor.
    static func read(_ photo: Data) -> NutritionLabel? {
        guard let image = UIImage(data: photo), let picture = image.cgImage else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // The words of a label are no sentences, and its numbers must stay as printed.
        request.usesLanguageCorrection = false
        if let supported = try? request.supportedRecognitionLanguages() {
            request.recognitionLanguages = languages.filter(supported.contains)
        }
        let handler = VNImageRequestHandler(cgImage: picture, orientation: orientation(of: image))
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let pieces = (request.results ?? []).compactMap(piece)
        return NutritionLabel.read(NutritionLabel.rows(pieces))
    }

    /// Vision measures from the bottom left; a piece is placed from the top, with the slope of its baseline.
    private static func piece(_ observation: VNRecognizedTextObservation) -> NutritionLabel.Piece? {
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        let box = observation.boundingBox
        let width = Double(observation.topRight.x - observation.topLeft.x)
        let slope = width > 0 ? -Double(observation.topRight.y - observation.topLeft.y) / width : 0
        return NutritionLabel.Piece(text: text, x: Double(box.midX), y: 1 - Double(box.midY), height: Double(box.height), slope: slope)
    }

    private static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
