import SwiftUI
import FitlingCore

/// A workout in progress: per exercise the advice, the sets so far and the next set to log, with
/// a rest timer after every working set.
struct WorkoutView: View {
    @State private var viewModel: WorkoutViewModel
    @State private var addingExercise = false
    @State private var confirmingDiscard = false
    @State private var records: [String] = []
    @Environment(\.dismiss) private var dismiss

    init(viewModel: WorkoutViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var languages: [String] { Locale.preferredLanguages }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.entries) { entry in
                    Section {
                        Text(viewModel.advice(for: entry).text(unit: viewModel.unit))
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSoft)
                        ForEach(Array(viewModel.sets(of: entry).enumerated()), id: \.element.id) { index, set in
                            setRow(set, number: index + 1)
                        }
                        .onDelete { offsets in
                            let sets = viewModel.sets(of: entry)
                            for index in offsets { viewModel.remove(sets[index]) }
                        }
                        draftRow(entry)
                    } header: {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(verbatim: entry.exercise.name.text(preferring: languages))
                                .font(.headline.weight(.heavy))
                            let rules = viewModel.rules(for: entry)
                            Text("training.workout.target \(rules.targetSets) \(rules.repRange.lowerBound) \(rules.repRange.upperBound)")
                                .font(.footnote)
                        }
                        .foregroundStyle(Color.ink)
                        .textCase(nil)
                    }
                    .listRowBackground(Color.card)
                }
                Section {
                    Button {
                        addingExercise = true
                    } label: {
                        Label("training.workout.addExercise", systemImage: "plus")
                    }
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .accessibilityIdentifier("workout.list")
            // The rest timer stays in view at the bottom, wherever the list is scrolled.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let restEndsAt = viewModel.restEndsAt {
                    RestTimer(endsAt: restEndsAt) { viewModel.skipRest() }
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.m)
                        .background(Color.ink)
                }
            }
            .navigationTitle(viewModel.title.map { Text(verbatim: $0.text(preferring: languages)) } ?? Text("training.session.free"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("training.workout.later") { dismiss() }
                        Button("training.workout.discard", role: .destructive) { confirmingDiscard = true }
                    } label: {
                        Label("training.workout.options", systemImage: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("training.workout.finish") {
                        records = viewModel.records().map { exercise, record in
                            record.text(exercise: exercise.name.text(preferring: languages), unit: viewModel.unit)
                        }
                        viewModel.finish()
                        if records.isEmpty { dismiss() }
                    }
                    .fontWeight(.bold)
                    .accessibilityIdentifier("workout.finish")
                }
            }
            .sheet(isPresented: $addingExercise) {
                ExercisePicker(store: viewModel.exerciseStore) { exercise, _, _, _ in
                    viewModel.add(exercise)
                }
            }
            .confirmationDialog("training.workout.discard.title", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("training.workout.discard", role: .destructive) {
                    viewModel.discard()
                    dismiss()
                }
            }
            .alert("training.records.title", isPresented: Binding(get: { !records.isEmpty }, set: { if !$0 { records = [] } })) {
                Button("common.ok") {
                    records = []
                    dismiss()
                }
            } message: {
                Text(verbatim: records.joined(separator: "\n"))
            }
        }
    }

    private func setRow(_ set: WorkoutSet, number: Int) -> some View {
        HStack {
            Text(verbatim: "\(number)")
                .font(.headline.weight(.heavy))
                .monospacedDigit()
                .frame(minWidth: 24, alignment: .leading)
            Text("training.set.summary \(viewModel.unit.format(kilograms: set.weightKg)) \(set.reps)")
                .monospacedDigit()
            Spacer()
            if set.isWarmup {
                Text("training.set.warmup").font(.footnote).foregroundStyle(Color.inkSoft)
            } else if let rpe = set.rpe {
                Text("training.set.rpe \(rpe.formatted(.number.precision(.fractionLength(0...1))))").font(.footnote).foregroundStyle(Color.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func draftRow(_ entry: WorkoutViewModel.Entry) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                HStack(spacing: Spacing.xs) {
                    TextField("training.set.weight", value: draftBinding(entry, \.weight), format: .number)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("workout.weight.\(entry.exercise.id.uuidString)")
                    Text(verbatim: viewModel.unit.symbol).foregroundStyle(Color.inkSoft)
                }
                HStack(spacing: Spacing.xs) {
                    TextField("training.set.reps", value: draftBinding(entry, \.reps), format: .number)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("workout.reps.\(entry.exercise.id.uuidString)")
                    Text("training.set.repsUnit").foregroundStyle(Color.inkSoft)
                }
            }
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            HStack {
                Picker("training.set.rpeLabel", selection: draftBinding(entry, \.rpe)) {
                    Text("training.set.rpeNone").tag(Double?.none)
                    ForEach(Array(stride(from: 6.0, through: 10.0, by: 0.5)), id: \.self) { value in
                        Text(verbatim: value.formatted(.number.precision(.fractionLength(0...1)))).tag(Double?.some(value))
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.ink)
                Spacer()
                Toggle("training.set.warmup", isOn: Binding(
                    get: { viewModel.drafts[entry.id]?.isWarmup ?? false },
                    set: { viewModel.drafts[entry.id, default: .init()].isWarmup = $0 }
                ))
                .fixedSize()
                .tint(Color.sprout)
            }
            Button {
                viewModel.log(entry)
            } label: {
                Text("training.set.log")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!viewModel.canLog(entry))
            .accessibilityIdentifier("workout.log.\(entry.exercise.id.uuidString)")
        }
        .padding(.vertical, Spacing.xs)
    }

    private func draftBinding<Value>(_ entry: WorkoutViewModel.Entry, _ keyPath: WritableKeyPath<WorkoutViewModel.Draft, Value>) -> Binding<Value> {
        Binding(
            get: { (viewModel.drafts[entry.id] ?? .init())[keyPath: keyPath] },
            set: { viewModel.drafts[entry.id, default: .init()][keyPath: keyPath] = $0 }
        )
    }
}

/// Counts down the rest after a set, in ink with card-coloured text.
private struct RestTimer: View {
    let endsAt: Date
    let onSkip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endsAt.timeIntervalSince(context.date).rounded(.up)))
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(remaining > 0 ? LocalizedStringKey("training.rest.title") : "training.rest.done")
                        .font(.subheadline.weight(.bold))
                    Text(Duration.seconds(remaining), format: .time(pattern: .minuteSecond))
                        .font(.largeTitle.weight(.heavy))
                        .monospacedDigit()
                }
                Spacer()
                Button(remaining > 0 ? LocalizedStringKey("training.rest.skip") : "common.ok", action: onSkip)
                    .buttonStyle(.borderless)
                    .fontWeight(.bold)
            }
            .foregroundStyle(Color.card)
        }
        .accessibilityIdentifier("workout.rest")
    }
}

extension ProgressionAdvice {
    func text(unit: WeightUnit) -> LocalizedStringKey {
        switch self {
        case .findStartingWeight: "training.advice.start"
        case let .keepGoing(weight): "training.advice.keepGoing \(unit.format(kilograms: weight))"
        case let .increase(weight): "training.advice.increase \(unit.format(kilograms: weight))"
        case let .addRepsFirst(weight, reps): "training.advice.addReps \(reps) \(unit.format(kilograms: weight))"
        case let .reduce(weight): "training.advice.reduce \(unit.format(kilograms: weight))"
        case let .easeBackIn(weight): "training.advice.easeBack \(unit.format(kilograms: weight))"
        case .makeHarder: "training.advice.harder"
        case .makeEasier: "training.advice.easier"
        }
    }
}

extension PersonalRecord {
    func text(exercise: String, unit: WeightUnit) -> String {
        switch self {
        case let .weight(kg): String(localized: "training.record.weight \(exercise) \(unit.format(kilograms: kg))")
        case let .estimatedOneRepMax(kg): String(localized: "training.record.oneRepMax \(exercise) \(unit.format(kilograms: kg))")
        case let .reps(count, kg): String(localized: "training.record.reps \(exercise) \(count) \(unit.format(kilograms: kg))")
        }
    }
}
