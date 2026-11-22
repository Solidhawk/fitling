import CoreGraphics
import Foundation
import ImageIO

/// A moving example of an exercise: a sheet of rendered frames and the order to show them in. Both come
/// from `design/oefeningen/3d`; the timing is never edited here (ARCHITECTURE D-21).
struct ExerciseAnimation: Equatable, Sendable {
    let id: UUID
    let fps: Int
    let frameCount: Int
    let columns: Int
    /// The frame to show at each step of one repetition, `fps` steps a second.
    let sequence: [Int]

    private struct Manifest: Decodable, Sendable {
        let fps: Int
        let frames: Int
        let columns: Int
        let animations: [String: [Int]]
    }

    private static let manifest: Manifest? = Bundle.main.url(forResource: "ExerciseAnimations", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }

    static func named(_ id: UUID) -> ExerciseAnimation? {
        guard let manifest, manifest.fps > 0, manifest.columns > 0,
              let sequence = manifest.animations[id.uuidString.lowercased()], !sequence.isEmpty
        else { return nil }
        return ExerciseAnimation(id: id, fps: manifest.fps, frameCount: manifest.frames, columns: manifest.columns, sequence: sequence)
    }

    var duration: TimeInterval { Double(sequence.count) / Double(fps) }

    /// The start and the end of the movement, for when nothing may move.
    var stillFrames: [Int] { [0, frameCount - 1] }

    func frame(at elapsed: TimeInterval) -> Int {
        let step = Int((max(elapsed, 0) * Double(fps)).rounded(.down))
        return sequence[step % sequence.count]
    }

    /// Decodes the sheet and cuts it into frames. Not on the main actor: it is 2640 × 1320 pixels.
    nonisolated func loadFrames() async -> ExerciseFrames? {
        guard let url = Bundle.main.url(forResource: id.uuidString.lowercased(), withExtension: "webp"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        let rows = (frameCount + columns - 1) / columns
        let width = sheet.width / columns
        let height = sheet.height / rows
        let images = (0..<frameCount).compactMap { index in
            sheet.cropping(to: CGRect(x: index % columns * width, y: index / columns * height, width: width, height: height))
        }
        return images.count == frameCount ? ExerciseFrames(images: images) : nil
    }
}

/// The decoded frames. Unchecked, because a `CGImage` never changes after it is made.
struct ExerciseFrames: @unchecked Sendable {
    let images: [CGImage]
}

/// Where the animation is in time, also across pauses.
struct AnimationPlayback: Equatable {
    private var startedAt: Date
    private var pausedAt: Date?

    init(startedAt: Date) {
        self.startedAt = startedAt
    }

    var isPaused: Bool { pausedAt != nil }

    func elapsed(at date: Date) -> TimeInterval {
        (pausedAt ?? date).timeIntervalSince(startedAt)
    }

    mutating func toggle(at date: Date) {
        if let paused = pausedAt {
            startedAt += date.timeIntervalSince(paused)
            pausedAt = nil
        } else {
            pausedAt = date
        }
    }
}
