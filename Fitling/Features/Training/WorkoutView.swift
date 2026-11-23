import SwiftUI
import FitlingCore

/// A workout in progress: per exercise the advice, the sets so far and the next set to log, with
/// a rest timer after every working set.
struct WorkoutView: View {
    @State private var viewModel: WorkoutViewModel
    @State private var addingExercise = false
    @State private var confirmingDiscard = false
    @State private var records: [String] = []
    @FocusState private var focus: SetField?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The field being typed in, so the keyboard's own button can save that exercise's set.
    private enum SetField: Hashable {
        case weight(UUID), reps(UUID)

        var entryID: UUID {
            switch self {
            case let .weight(id), let .reps(id): id
            }
        }
    }

    init(viewModel: WorkoutViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var languages: [String] { Locale.preferredLanguages }

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.entries) { entry in
                    Section {
                        // The animation and how it is done, without leaving the workout.
                        NavigationLink {
                            ExerciseProgressView(exercise: entry.exercise, store: viewModel.exerciseStore)
                        } label: {
                            Label("training.exercise.explain", systemImage: "info.circle")
                        }
                        .accessibilityIdentifier("workout.exercise.\(entry.exercise.id.uuidString.lowercased())")
                        adviceText(for: entry)
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
                // Saving from above the keyboard: with the largest text the row's own button is under it.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("training.set.log") { logFocusedSet() }
                        .fontWeight(.bold)
                        .disabled(focusedEntry.map { !viewModel.canLog($0) } ?? true)
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

    /// The advice for the exercise. The long first-time advice is shown once, at the first exercise
    /// it applies to; later ones point back to it.
    private func adviceText(for entry: WorkoutViewModel.Entry) -> Text {
        let advice = viewModel.advice(for: entry)
        let firstNew = viewModel.entries.first { viewModel.advice(for: $0) == .findStartingWeight }?.id
        if advice == .findStartingWeight, entry.id != firstNew {
            return Text("training.advice.startAgain")
        }
        return Text(advice.text(unit: viewModel.unit))
    }

    private var focusedEntry: WorkoutViewModel.Entry? {
        focus.flatMap { field in viewModel.entries.first { $0.id == field.entryID } }
    }

    private func logFocusedSet() {
        guard let entry = focusedEntry, viewModel.canLog(entry) else { return }
        viewModel.log(entry)
        focus = nil
    }

    /// A number with its label above it and its unit beside it, on a field background, so weight
    /// and reps never read as one value.
    private func numberField<Field: View>(_ label: LocalizedStringKey, unit: Text, focusing target: SetField, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.inkSoft)
            HStack(spacing: Spacing.xs) {
                field()
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                unit.foregroundStyle(Color.inkSoft)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(Color.ground, in: RoundedRectangle(cornerRadius: Radius.card / 2, style: .continuous))
            // A tap anywhere on the box puts the cursor in the field, not only a tap on the digits.
            .contentShape(RoundedRectangle(cornerRadius: Radius.card / 2, style: .continuous))
            .onTapGesture { focus = target }
        }
    }

    private func draftRow(_ entry: WorkoutViewModel.Entry) -> some View {
        // Side by side normally; under each other at the accessibility sizes, where one field
        // already fills the width.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let fields = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: Spacing.m))
        let options = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s))
            : AnyLayout(HStackLayout(spacing: Spacing.s))
        return VStack(alignment: .leading, spacing: Spacing.s) {
            fields {
                numberField("training.set.weight", unit: Text(verbatim: viewModel.unit.symbol), focusing: .weight(entry.id)) {
                    TextField("training.set.weight", value: draftBinding(entry, \.weight), format: .number)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .weight(entry.id))
                        .accessibilityIdentifier("workout.weight.\(entry.exercise.id.uuidString)")
                }
                numberField("training.set.reps", unit: Text("training.set.repsUnit"), focusing: .reps(entry.id)) {
                    TextField("training.set.reps", value: draftBinding(entry, \.reps), format: .number)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .reps(entry.id))
                        .accessibilityIdentifier("workout.reps.\(entry.exercise.id.uuidString)")
                }
            }
            options {
                Picker("training.set.rpeLabel", selection: draftBinding(entry, \.rpe)) {
                    Text("training.set.rpeNone").tag(Double?.none)
                    ForEach(Array(stride(from: 6.0, through: 10.0, by: 0.5)), id: \.self) { value in
                        Text(verbatim: value.formatted(.number.precision(.fractionLength(0...1)))).tag(Double?.some(value))
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.ink)
                if !stacked { Spacer() }
                Toggle("training.set.warmup", isOn: Binding(
                    get: { viewModel.drafts[entry.id]?.isWarmup ?? false },
                    set: { viewModel.drafts[entry.id, default: .init()].isWarmup = $0 }
                ))
                .fixedSize(horizontal: !stacked, vertical: false)
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
