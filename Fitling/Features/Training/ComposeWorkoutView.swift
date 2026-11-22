import SwiftUI
import FitlingCore

/// Compose a workout: say how long and what to train, see the exercises the app picks for it, and start.
struct ComposeWorkoutView: View {
    @Bindable var viewModel: TrainingViewModel
    let onStart: (WorkoutSession) -> Void
    @State private var focus: TrainingFocus = .upperBody
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let plan = viewModel.plan(for: focus)
        NavigationStack {
            List {
                Section {
                    Picker("training.compose.time", selection: $viewModel.workoutMinutes) {
                        ForEach(WorkoutBuilder.durations, id: \.self) { minutes in
                            Text("training.compose.minutes \(minutes)").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.ink)
                    .accessibilityIdentifier("training.compose.duration")
                } header: {
                    Text("training.compose.duration")
                } footer: {
                    if !plan.exercises.isEmpty {
                        timeFooter(plan)
                    }
                }
                .listRowBackground(Color.card)

                Section("training.compose.focus") {
                    Picker("training.compose.focus", selection: $focus) {
                        ForEach(TrainingFocus.allCases, id: \.self) { focus in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(focus.titleResource)
                                Text(verbatim: focus.muscleList)
                                    .font(.footnote)
                                    .foregroundStyle(Color.inkSoft)
                            }
                            .tag(focus)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .tint(Color.ink)
                }
                .listRowBackground(Color.card)

                Section {
                    if plan.exercises.isEmpty {
                        Text("training.compose.none")
                    }
                    ForEach(plan.exercises, id: \.exerciseID) { planned in
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: viewModel.store.exercise(planned.exerciseID)?.name.text(preferring: Locale.preferredLanguages) ?? "")
                            Spacer(minLength: Spacing.s)
                            Text("training.compose.sets \(planned.sets) \(planned.repRange.lowerBound) \(planned.repRange.upperBound)")
                                .fontWeight(.heavy)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("training.compose.exercises")
                } footer: {
                    Text("training.compose.footer").footerStyle()
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .safeAreaInset(edge: .bottom) {
                Button {
                    let session = viewModel.startComposed(focus)
                    onStart(session)
                    dismiss()
                } label: {
                    Text("training.compose.start")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(plan.exercises.isEmpty)
                .accessibilityIdentifier("training.compose.start")
                .padding(Spacing.l)
                .background(Color.ground)
            }
            .navigationTitle("training.compose.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
    }

    /// What the chosen time gives: the estimate, and what it costs or leaves over.
    private func timeFooter(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("training.compose.estimate \(plan.roundedMinutes)").footerStyle()
            if plan.minutes <= WorkoutBuilder.shortWorkoutMinutes {
                Text("training.compose.short").footerStyle()
            }
            if !plan.leftOut.isEmpty {
                Text("training.compose.leftOut \(plan.leftOut.inSentence)").footerStyle()
            }
            if plan.leavesTimeOver {
                Text("training.compose.timeOver").footerStyle()
            }
        }
    }
}

extension [MuscleGroup] {
    /// "borst, rug en schouders", for inside a sentence.
    var inSentence: String {
        map { $0.displayName.lowercased(with: .current) }.formatted(.list(type: .and))
    }
}

extension TrainingFocus {
    /// "Borst, rug, schouders, biceps en triceps": the muscle names are titles on their own, so in a
    /// sentence only the first keeps its capital.
    var muscleList: String {
        let list = muscles.inSentence
        return list.prefix(1).uppercased(with: .current) + list.dropFirst()
    }

    var titleResource: LocalizedStringResource {
        switch self {
        case .fullBody: "training.focus.fullBody"
        case .upperBody: "training.focus.upperBody"
        case .lowerBody: "training.focus.lowerBody"
        case .push: "training.focus.push"
        case .pull: "training.focus.pull"
        case .arms: "training.focus.arms"
        }
    }
}
