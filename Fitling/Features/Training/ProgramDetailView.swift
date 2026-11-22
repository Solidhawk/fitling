import SwiftUI
import FitlingCore

/// One programme: its days with their exercises. A ready-made programme can be started or copied;
/// the user's own can also be changed.
struct ProgramDetailView: View {
    let program: Program
    let store: TrainingStore
    let onStart: (ProgramDay) -> Void
    let onOpenCopy: (Program) -> Void
    @State private var days: [ProgramDay] = []
    @State private var itemsByDay: [UUID: [ProgramExercise]] = [:]
    @State private var addingTo: ProgramDay?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    init(program: Program, store: TrainingStore, onStart: @escaping (ProgramDay) -> Void, onOpenCopy: @escaping (Program) -> Void) {
        self.program = program
        self.store = store
        self.onStart = onStart
        self.onOpenCopy = onOpenCopy
    }

    private var isOwn: Bool { program.ownerID == store.userID }
    private var languages: [String] { Locale.preferredLanguages }

    var body: some View {
        List {
            ForEach(days) { day in
                Section {
                    ForEach(itemsByDay[day.id] ?? []) { item in
                        itemRow(item)
                    }
                    .onDelete(perform: store.canChange(day) ? deletion(from: day) : nil)
                    if store.canChange(day) {
                        Button {
                            addingTo = day
                        } label: {
                            Label("training.program.addExercise", systemImage: "plus")
                        }
                    }
                    Button {
                        onStart(day)
                    } label: {
                        Label("training.program.start", systemImage: "play.fill")
                            .fontWeight(.bold)
                    }
                    .disabled((itemsByDay[day.id] ?? []).isEmpty)
                    .accessibilityIdentifier("training.start.\(day.position)")
                } header: {
                    Text(verbatim: title(of: day))
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color.ink)
                        .textCase(nil)
                }
                .listRowBackground(Color.card)
            }
        }
        .foregroundStyle(Color.ink)
        .groundBackground()
        .accessibilityIdentifier("program.list")
        .navigationTitle(Text(verbatim: program.name.text(preferring: languages)))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isOwn {
                    Menu {
                        Button("training.program.rename") {
                            newName = program.name.text(preferring: languages)
                            renaming = true
                        }
                        Button("training.program.delete", role: .destructive) { confirmingDelete = true }
                    } label: {
                        Label("training.program.options", systemImage: "ellipsis.circle")
                    }
                } else {
                    Button("training.program.copy") {
                        let name = String(localized: "training.program.copyName \(program.name.text(preferring: languages))")
                        onOpenCopy(store.copy(program, named: name))
                    }
                }
            }
        }
        .onAppear(perform: reload)
        .sheet(item: $addingTo, onDismiss: reload) { day in
            ExercisePicker(store: store) { exercise, sets, range, rest in
                store.add(exercise, to: day, sets: sets, repRange: range, restSeconds: rest)
            }
        }
        .alert("training.program.rename", isPresented: $renaming) {
            TextField("training.program.name", text: $newName)
            Button("common.cancel", role: .cancel) {}
            Button("common.save") {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { store.rename(program, to: trimmed) }
            }
        }
        .confirmationDialog("training.program.delete.title", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("training.program.delete", role: .destructive) {
                store.delete(program)
                dismiss()
            }
        } message: {
            Text("training.program.delete.body")
        }
    }

    private func itemRow(_ item: ProgramExercise) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: store.exercise(item.exerciseID)?.name.text(preferring: languages) ?? "")
            Text("training.item.detail \(item.targetSets) \(item.repMin) \(item.repMax) \(item.restSeconds)")
                .font(.footnote)
                .foregroundStyle(Color.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }

    /// A composed day carries its date, or ten times "Bovenlichaam" could not be told apart. It is never changed
    /// after it is made, so `updatedAt` is when that was.
    private func title(of day: ProgramDay) -> String {
        let name = day.name.text(preferring: languages)
        guard ComposedWorkout.focus(of: day.id) != nil else { return name }
        return "\(name) · \(day.updatedAt.formatted(.dateTime.day().month()))"
    }

    private func reload() {
        days = store.daysToShow(of: program)
        itemsByDay = Dictionary(uniqueKeysWithValues: days.map { ($0.id, store.items(of: $0)) })
    }

    private func deletion(from day: ProgramDay) -> (IndexSet) -> Void {
        { offsets in
            let items = itemsByDay[day.id] ?? []
            for index in offsets { store.remove(items[index]) }
            reload()
        }
    }
}

/// Picks an exercise and how it is trained: sets, rep range and rest.
struct ExercisePicker: View {
    let store: TrainingStore
    let onPick: (Exercise, Int, ClosedRange<Int>, Int) -> Void
    @State private var query = ""
    @State private var chosen: Exercise?
    @State private var sets = 3
    @State private var repMin = 8
    @State private var repMax = 12
    @State private var rest = 120
    @Environment(\.dismiss) private var dismiss

    init(store: TrainingStore, onPick: @escaping (Exercise, Int, ClosedRange<Int>, Int) -> Void) {
        self.store = store
        self.onPick = onPick
    }

    private var languages: [String] { Locale.preferredLanguages }

    private var matches: [Exercise] {
        let all = store.exercises()
        let term = FoodDiary.searchKey(query)
        guard !term.isEmpty else { return all }
        return all.filter { FoodDiary.searchKey($0.name.text(preferring: languages)).contains(term) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let chosen {
                    Section {
                        Text(verbatim: chosen.name.text(preferring: languages)).font(.headline.weight(.heavy))
                        Stepper(value: $sets, in: 1...10) { Text("training.picker.sets \(sets)") }
                        Stepper(value: $repMin, in: 1...repMax) { Text("training.picker.repMin \(repMin)") }
                        Stepper(value: $repMax, in: repMin...100) { Text("training.picker.repMax \(repMax)") }
                        Stepper(value: $rest, in: 0...900, step: 15) { Text("training.picker.rest \(rest)") }
                    }
                    .listRowBackground(Color.card)
                } else {
                    Section {
                        ForEach(matches) { exercise in
                            Button {
                                chosen = exercise
                                if ExerciseKind(rawValue: exercise.kind) == .isolation {
                                    repMin = 10
                                    repMax = 15
                                    rest = 60
                                }
                            } label: {
                                ExerciseRow(exercise: exercise)
                            }
                        }
                    }
                    .listRowBackground(Color.card)
                }
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .searchable(text: $query, prompt: Text("training.picker.search"))
            .navigationTitle("training.picker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                if let chosen {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.save") {
                            onPick(chosen, sets, repMin...max(repMin, repMax), rest)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

/// An exercise with its main muscle groups, as a list row.
struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: EquipmentKind(rawValue: exercise.equipment)?.symbol ?? "figure.strengthtraining.traditional")
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: exercise.name.text(preferring: Locale.preferredLanguages)).foregroundStyle(Color.ink)
                Text(verbatim: exercise.primaryMuscles.compactMap { MuscleGroup(rawValue: $0)?.displayName }.formatted(.list(type: .and)))
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The equipment values of the `exercises` table, with an SF Symbol each.
enum EquipmentKind: String {
    case barbell, dumbbell, machine, cable, kettlebell, band, bodyweight, other

    var symbol: String {
        switch self {
        case .barbell, .dumbbell: "dumbbell"
        case .machine, .cable: "figure.strengthtraining.functional"
        case .kettlebell: "figure.cross.training"
        case .band: "figure.flexibility"
        case .bodyweight: "figure.strengthtraining.traditional"
        case .other: "figure.mixed.cardio"
        }
    }
}

extension MuscleGroup {
    var displayName: String {
        switch self {
        case .chest: String(localized: "muscle.chest")
        case .back: String(localized: "muscle.back")
        case .shoulders: String(localized: "muscle.shoulders")
        case .biceps: String(localized: "muscle.biceps")
        case .triceps: String(localized: "muscle.triceps")
        case .forearms: String(localized: "muscle.forearms")
        case .core: String(localized: "muscle.core")
        case .glutes: String(localized: "muscle.glutes")
        case .quads: String(localized: "muscle.quads")
        case .hamstrings: String(localized: "muscle.hamstrings")
        case .calves: String(localized: "muscle.calves")
        }
    }
}
