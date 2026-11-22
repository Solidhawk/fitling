import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

/// The animations of the exercises without a drawing (UNFORGET S19).
@MainActor
@Suite struct ExerciseAnimationTests {
    static let gobletSquat = UUID(uuidString: "3b70d0ec-e441-5831-808c-0c025c473ebf")!

    @Test func everyExerciseHasEitherADrawingOrAnAnimation() throws {
        let catalog = try #require(SportCatalog.bundled())
        for entry in catalog.exercises {
            let shown = [ExerciseDrawing.exists(for: entry.id), ExerciseAnimation.named(entry.id) != nil].filter { $0 }
            #expect(shown.count == 1, "\(entry.name.values["en"] ?? "")")
        }
    }

    @Test func anExerciseOfTheUsersOwnHasNoAnimation() {
        #expect(ExerciseAnimation.named(UUID()) == nil)
    }

    @Test func everyAnimationsPictureDecodesIntoItsFrames() async throws {
        let catalog = try #require(SportCatalog.bundled())
        let animations = catalog.exercises.compactMap { ExerciseAnimation.named($0.id) }
        #expect(animations.count == 7)
        for animation in animations {
            let frames = try #require(await animation.loadFrames(), "\(animation.id)")
            #expect(frames.images.count == 40)
            #expect(frames.images.allSatisfy { $0.width == 440 && $0.height == 330 })
            #expect(animation.sequence.allSatisfy { frames.images.indices.contains($0) })
        }
    }

    @Test func theFramesFollowTheTimingAndStartOver() throws {
        let animation = try #require(ExerciseAnimation.named(Self.gobletSquat))
        let steps = animation.sequence.count
        for step in [0, 1, 20, steps - 1] {
            let time = (Double(step) + 0.5) / Double(animation.fps)
            #expect(animation.frame(at: time) == animation.sequence[step])
            #expect(animation.frame(at: time + animation.duration) == animation.sequence[step])
        }
    }

    @Test func aTimeBeforeTheStartShowsTheStart() throws {
        let animation = try #require(ExerciseAnimation.named(Self.gobletSquat))
        #expect(animation.frame(at: -1) == animation.sequence[0])
    }

    @Test func pausingHoldsTheFrameAndPlayingGoesOnFromThere() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var playback = AnimationPlayback(startedAt: start)
        #expect(playback.elapsed(at: start + 2) == 2)

        playback.toggle(at: start + 2)
        #expect(playback.isPaused)
        #expect(playback.elapsed(at: start + 9) == 2)

        playback.toggle(at: start + 10)
        #expect(!playback.isPaused)
        #expect(playback.elapsed(at: start + 11) == 3)
    }

    @Test func stillFramesAreTheStartAndTheEndOfTheMovement() throws {
        let animation = try #require(ExerciseAnimation.named(Self.gobletSquat))
        #expect(animation.stillFrames == [0, 39])
    }

    @Test func theUITestHistoryHasEveryAnimatedExercise() throws {
        let fixture = try TrainingFixture()
        UITestEnvironment.insertAnimatedExerciseHistory(
            userID: fixture.userID, into: fixture.context, defaults: fixture.defaults, now: fixture.now, timeZone: .gmt
        )
        let done = fixture.store.exercises().filter { !fixture.store.history(of: $0.id).isEmpty }
        #expect(done.count == 7)
        #expect(done.allSatisfy { ExerciseAnimation.named($0.id) != nil })
    }
}
