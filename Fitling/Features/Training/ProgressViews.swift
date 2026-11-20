import Charts
import SwiftUI
import FitlingCore

/// Exercises with logged working sets, to open their progress.
struct ExerciseProgressList: View {
    let store: TrainingStore
    let onOpen: (Exercise) -> Void
    @State private var exercises: [Exercise] = []

    init(store: TrainingStore, onOpen: @escaping (Exercise) -> Void) {
        self.store = store
        self.onOpen = onOpen
    }

    var body: some View {
        List {
            if exercises.isEmpty {
                Text("training.progress.empty").footerStyle().listRowBackground(Color.clear)
            }
            ForEach(exercises) { exercise in
                Button {
                    onOpen(exercise)
                } label: {
                    ExerciseRow(exercise: exercise)
                }
            }
            .listRowBackground(Color.card)
        }
        .foregroundStyle(Color.ink)
        .groundBackground()
        .navigationTitle("training.progress.exercises")
        .onAppear {
            exercises = store.exercises().filter { !store.history(of: $0.id).isEmpty }
        }
    }
}

/// One exercise over time: the estimated one-rep max per workout (Epley), the records, the
/// advice for next time and the user's own weight step.
struct ExerciseProgressView: View {
    let exercise: Exercise
    let store: TrainingStore
    @State private var history: [ExerciseSession] = []
    @State private var step: Double = 2.5
    private let unit = WeightUnit(locale: .current)

    init(exercise: Exercise, store: TrainingStore) {
        self.exercise = exercise
        self.store = store
    }

    /// The best estimate of each workout; sets over 12 reps give none.
    private var points: [(date: Date, kg: Double)] {
        history.compactMap { session in
            session.sets.compactMap { ProgressionEngine.estimatedOneRepMax(weightKg: $0.weightKg, reps: $0.reps) }.max()
                .map { (session.day.startDate, $0) }
        }
    }

    var body: some View {
        List {
            if ExerciseDrawing.exists(for: exercise.id) {
                Section {
                    ExerciseDrawing(exerciseID: exercise.id)
                } footer: {
                    Text("training.drawing.credit").footerStyle()
                }
                .listRowBackground(Color.card)
            }
            Section {
                if points.count >= 2 {
                    Chart(points, id: \.date) { point in
                        LineMark(x: .value("training.chart.date", point.date), y: .value("training.chart.oneRepMax", unit.value(fromKilograms: point.kg)))
                            .foregroundStyle(Color.ink)
                        PointMark(x: .value("training.chart.date", point.date), y: .value("training.chart.oneRepMax", unit.value(fromKilograms: point.kg)))
                            .foregroundStyle(Color.ink)
                    }
                    .chartYAxisLabel(unit.symbol)
                    .frame(height: 200)
                    .accessibilityLabel(Text("training.chart.oneRepMax"))
                } else {
                    Text("training.chart.needsTwo").footerStyle()
                }
            } header: {
                Text("training.chart.oneRepMax")
            } footer: {
                Text("training.chart.footer").footerStyle()
            }
            .listRowBackground(Color.card)

            Section("training.records.title") {
                if let heaviest = history.flatMap(\.sets).map(\.weightKg).max() {
                    LabeledContent("training.records.heaviest") { Text(verbatim: unit.format(kilograms: heaviest)).monospacedDigit() }
                }
                if let best = points.map(\.kg).max() {
                    LabeledContent("training.records.oneRepMax") { Text(verbatim: unit.format(kilograms: best)).monospacedDigit() }
                }
                LabeledContent("training.records.workouts") { Text(verbatim: "\(history.count)").monospacedDigit() }
            }
            .listRowBackground(Color.card)

            Section {
                Text(store.advice(for: exercise, in: nil).text(unit: unit))
                Stepper(value: $step, in: 0.25...25, step: 0.25) {
                    Text("training.step.label \(unit.format(kilograms: step))")
                }
                .onChange(of: step) { _, value in
                    // Opening the screen sets the stepper too; only a real change is stored.
                    if value != store.setting(for: exercise.id)?.stepKg ?? exercise.defaultStepKg {
                        store.saveStep(value, for: exercise)
                    }
                }
            } header: {
                Text("training.step.title")
            } footer: {
                Text("training.step.footer").footerStyle()
            }
            .listRowBackground(Color.card)

            if !exercise.instructions.isEmpty {
                Section("training.instructions") {
                    Text(verbatim: exercise.instructions.text(preferring: Locale.preferredLanguages))
                }
                .listRowBackground(Color.card)
            }
        }
        .foregroundStyle(Color.ink)
        .groundBackground()
        .navigationTitle(Text(verbatim: exercise.name.text(preferring: Locale.preferredLanguages)))
        .onAppear {
            history = store.history(of: exercise.id)
            step = store.setting(for: exercise.id)?.stepKg ?? exercise.defaultStepKg
        }
    }
}

/// Hard sets per muscle group this week and last week (`ProgressionEngine.weeklyVolume`).
struct VolumeView: View {
    let store: TrainingStore
    @State private var weeks: [Day: [MuscleGroup: MuscleVolume]] = [:]
    @State private var showsLastWeek = false

    init(store: TrainingStore) {
        self.store = store
    }

    private var week: Day {
        showsLastWeek ? store.today.weekStart.adding(-7) : store.today.weekStart
    }

    private var bars: [(muscle: MuscleGroup, sets: Double)] {
        MuscleGroup.allCases.compactMap { muscle in
            weeks[week]?[muscle].map { (muscle, $0.sets) }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("training.volume.week", selection: $showsLastWeek) {
                    Text("training.volume.thisWeek").tag(false)
                    Text("training.volume.lastWeek").tag(true)
                }
                .pickerStyle(.segmented)
                if bars.isEmpty {
                    Text("training.volume.empty").footerStyle()
                } else {
                    Chart(bars, id: \.muscle) { bar in
                        BarMark(x: .value("training.volume.sets", bar.sets), y: .value("training.volume.muscle", bar.muscle.displayName))
                            .foregroundStyle(Color.ink)
                            .annotation(position: .trailing) {
                                Text(verbatim: bar.sets.formatted(.number.precision(.fractionLength(0...1))))
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(Color.ink)
                            }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(bars.count) * 36 + 16)
                }
            } footer: {
                Text("training.volume.footer").footerStyle()
            }
            .listRowBackground(Color.card)
        }
        .foregroundStyle(Color.ink)
        .groundBackground()
        .navigationTitle("training.progress.volume")
        .onAppear(perform: load)
    }

    private func load() {
        let since = store.today.weekStart.adding(-7)
        var logged: [LoggedExercise] = []
        for exercise in store.exercises() {
            let primary = exercise.primaryMuscles.compactMap(MuscleGroup.init(rawValue:))
            let secondary = exercise.secondaryMuscles.compactMap(MuscleGroup.init(rawValue:))
            for session in store.history(of: exercise.id) where session.day >= since {
                logged.append(LoggedExercise(day: session.day, primaryMuscles: primary, secondaryMuscles: secondary, sets: session.sets))
            }
        }
        weeks = ProgressionEngine.weeklyVolume(logged)
    }
}

/// The start and end position of an exercise, as line drawings in ink. Drawings by Everkinetic
/// (CC BY-SA 4.0), recoloured; not every exercise has one.
struct ExerciseDrawing: View {
    let exerciseID: UUID

    static func exists(for exerciseID: UUID) -> Bool {
        UIImage(named: "Exercises/\(exerciseID.uuidString.lowercased())-start") != nil
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.l) {
            ForEach(["start", "end"], id: \.self) { phase in
                Image("Exercises/\(exerciseID.uuidString.lowercased())-\(phase)")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, maxHeight: 180)
            }
        }
        .padding(.vertical, Spacing.s)
        .accessibilityHidden(true)
    }
}
