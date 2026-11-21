import SwiftUI
import FitlingCore

/// Compose a workout: pick what to train, see the exercises the app picks for it, and start.
struct ComposeWorkoutView: View {
    let viewModel: TrainingViewModel
    let onStart: (WorkoutSession) -> Void
    @State private var focus: TrainingFocus = .upperBody
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let plan = viewModel.plan(for: focus)
        NavigationStack {
            List {
                Section("training.compose.focus") {
                    Picker("training.compose.focus", selection: $focus) {
                        ForEach(TrainingFocus.allCases, id: \.self) { focus in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(focus.titleResource)
                                Text(verbatim: focus.muscles.map(\.displayName).formatted(.list(type: .and)))
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
                    if plan.isEmpty {
                        Text("training.compose.none")
                    }
                    ForEach(plan, id: \.exerciseID) { planned in
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
                .disabled(plan.isEmpty)
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
}

extension TrainingFocus {
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
