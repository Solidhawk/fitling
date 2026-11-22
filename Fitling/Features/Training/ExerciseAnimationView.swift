import SwiftUI

/// The exercise done by a figure, over and over; a tap pauses it. With Reduce Motion on, the start and
/// the end of the movement stand still next to each other.
struct ExerciseAnimationView: View {
    let animation: ExerciseAnimation
    @State private var frames: ExerciseFrames?
    @State private var playback = AnimationPlayback(startedAt: .now)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The frames are 440 × 330 pixels.
    private static let shape: CGFloat = 4.0 / 3.0
    private static let maxHeight: CGFloat = 240

    init(animation: ExerciseAnimation) {
        self.animation = animation
    }

    private var standsStill: Bool {
        #if DEBUG
        if UITestEnvironment.reducesMotion { return true }
        #endif
        return reduceMotion
    }

    var body: some View {
        Group {
            if let frames {
                if standsStill {
                    stills(frames)
                } else {
                    player(frames)
                }
            } else {
                // Holds the place, so the screen does not jump when the frames are in.
                Color.clear
                    .aspectRatio(Self.shape, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Self.maxHeight)
            }
        }
        .task(id: animation.id) {
            frames = await animation.loadFrames()
            playback = AnimationPlayback(startedAt: .now)
        }
    }

    private func player(_ frames: ExerciseFrames) -> some View {
        Button {
            playback.toggle(at: .now)
        } label: {
            TimelineView(.animation(minimumInterval: 1 / Double(animation.fps), paused: playback.isPaused)) { timeline in
                picture(frames.images[animation.frame(at: playback.elapsed(at: timeline.date))])
            }
            .frame(maxWidth: .infinity, maxHeight: Self.maxHeight)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: playback.isPaused ? "play.fill" : "pause.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(playback.isPaused ? LocalizedStringKey("training.animation.play") : "training.animation.pause"))
        .accessibilityIdentifier("exercise.animation")
    }

    private func stills(_ frames: ExerciseFrames) -> some View {
        HStack(spacing: Spacing.s) {
            ForEach(animation.stillFrames, id: \.self) { index in
                picture(frames.images[index]).frame(maxWidth: .infinity, maxHeight: Self.maxHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("training.animation.still"))
        .accessibilityIdentifier("exercise.animation.still")
    }

    private func picture(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(Self.shape, contentMode: .fit)
    }
}
