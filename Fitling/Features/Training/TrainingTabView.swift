import SwiftUI
import SwiftData
import FitlingCore

enum TrainingRoute: Hashable {
    case program(UUID)
    case exercises
    case exercise(UUID)
    case volume
    case body
    case photos
}

/// The composer, opened on a focus.
private struct ComposeRequest: Identifiable {
    let id = UUID()
    let focus: TrainingFocus
}

/// The training tab: carry on with a workout or start the next one, the programmes, progress
/// and recent workouts.
struct TrainingTabView: View {
    @State private var viewModel: TrainingViewModel
    @State private var path: [TrainingRoute] = []
    @State private var workout: WorkoutSession?
    @State private var creatingProgram = false
    @State private var composing: ComposeRequest?
    /// A composed workout waits until its sheet is gone before it opens full screen.
    @State private var composed: WorkoutSession?
    private let sync: SyncEngine

    init(profile: UserProfile, sync: SyncEngine, health: any HealthReading) {
        _viewModel = State(initialValue: TrainingViewModel(profile: profile, context: sync.context, health: health))
        self.sync = sync
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let active = viewModel.activeSession {
                    Section("training.active.title") {
                        Button {
                            workout = active
                        } label: {
                            sessionLabel(active, systemImage: "play.circle.fill")
                        }
                        .accessibilityIdentifier("training.resume")
                    }
                    .listRowBackground(Color.card)
                } else if let next = viewModel.next {
                    Section("training.next.title") {
                        nextButton(next)
                    }
                    .listRowBackground(Color.card)
                }

                Section {
                    if viewModel.activeSession == nil {
                        Button {
                            composing = ComposeRequest(focus: .upperBody)
                        } label: {
                            Label("training.compose.title", systemImage: "list.bullet.rectangle")
                        }
                        .accessibilityIdentifier("training.compose")
                    }
                    ForEach(viewModel.coachNotes) { note in
                        coachRow(note)
                    }
                } header: {
                    Text("training.coach.title")
                } footer: {
                    if viewModel.coachNotes.isEmpty {
                        Text("training.coach.empty").footerStyle()
                    }
                }
                .listRowBackground(Color.card)

                Section {
                    ForEach(viewModel.programs) { program in
                        NavigationLink(value: TrainingRoute.program(program.id)) {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(verbatim: program.name.text(preferring: Locale.preferredLanguages))
                                Text(program.ownerID == nil ? LocalizedStringKey("training.program.shared \(program.daysPerWeek)") : "training.program.own \(program.daysPerWeek)")
                                    .font(.footnote)
                                    .foregroundStyle(Color.inkSoft)
                            }
                        }
                        .accessibilityIdentifier("training.program.\(program.id.uuidString)")
                    }
                    Button {
                        creatingProgram = true
                    } label: {
                        Label("training.program.new", systemImage: "plus")
                    }
                } header: {
                    Text("training.programs.title")
                }
                .listRowBackground(Color.card)

                Section("training.progress.title") {
                    NavigationLink(value: TrainingRoute.exercises) { Label("training.progress.exercises", systemImage: "chart.line.uptrend.xyaxis") }
                    NavigationLink(value: TrainingRoute.volume) { Label("training.progress.volume", systemImage: "chart.bar") }
                    NavigationLink(value: TrainingRoute.body) { Label("body.title", systemImage: "scalemass") }
                    NavigationLink(value: TrainingRoute.photos) { Label("photos.title", systemImage: "photo.on.rectangle") }
                }
                .listRowBackground(Color.card)

                Section {
                    Toggle(
                        "training.health.toggle",
                        isOn: Binding(get: { viewModel.countsWorkoutEnergy }, set: { isOn in Task { await viewModel.setCountsWorkoutEnergy(isOn) } })
                    )
                    .tint(Color.sprout)
                } header: {
                    Text("training.health.title")
                } footer: {
                    Text(viewModel.healthRefused ? LocalizedStringKey("training.health.refused") : "training.health.footer").footerStyle()
                }
                .listRowBackground(Color.card)

                if !viewModel.recent.isEmpty {
                    Section("training.recent.title") {
                        ForEach(viewModel.recent) { session in
                            sessionLabel(session, systemImage: "checkmark.circle")
                                .accessibilityIdentifier("training.recent")
                        }
                    }
                    .listRowBackground(Color.card)
                }
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .accessibilityIdentifier("training.list")
            .navigationTitle("training.title")
            .navigationDestination(for: TrainingRoute.self) { route in
                destination(route)
            }
            .onAppear { viewModel.reload() }
            .task { await viewModel.importHealth() }
            .sheet(isPresented: $creatingProgram) {
                NewProgramSheet { name, days in
                    let program = viewModel.store.createProgram(named: name, daysPerWeek: days) { String(localized: "training.day.default \($0)") }
                    viewModel.reload()
                    path.append(.program(program.id))
                }
            }
            .sheet(item: $composing, onDismiss: {
                if let composed {
                    workout = composed
                    self.composed = nil
                }
            }) { request in
                ComposeWorkoutView(viewModel: viewModel, focus: request.focus) { composed = $0 }
            }
            .fullScreenCover(item: $workout, onDismiss: {
                viewModel.reload()
                Task { await sync.sync() }
            }) { session in
                WorkoutView(viewModel: WorkoutViewModel(session: session, store: viewModel.store))
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: TrainingRoute) -> some View {
        switch route {
        case let .program(id):
            if let program = viewModel.store.program(id) {
                ProgramDetailView(
                    program: program, store: viewModel.store,
                    onStart: { day in workout = viewModel.start(day) },
                    onOpenCopy: { copy in
                        viewModel.reload()
                        path.removeLast()
                        path.append(.program(copy.id))
                    }
                )
            }
        case .exercises:
            ExerciseProgressList(store: viewModel.store) { path.append(.exercise($0.id)) }
        case let .exercise(id):
            if let exercise = viewModel.store.exercise(id) {
                ExerciseProgressView(exercise: exercise, store: viewModel.store)
            }
        case .volume:
            VolumeView(store: viewModel.store)
        case .body:
            BodyView(log: BodyLog(context: viewModel.store.context, userID: viewModel.profile.id))
        case .photos:
            ProgressPhotosView(store: ProgressPhotoStore(context: viewModel.store.context))
        }
    }

    /// The next day of a programme starts; the next composed workout is composed first, so the time still counts.
    private func nextButton(_ next: NextWorkout) -> some View {
        Button {
            switch next {
            case let .programDay(_, day): workout = viewModel.start(day)
            case let .compose(focus): composing = ComposeRequest(focus: focus)
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                switch next {
                case let .programDay(program, day):
                    Text(verbatim: day.name.text(preferring: Locale.preferredLanguages)).font(.headline.weight(.heavy))
                    Text(verbatim: program.name.text(preferring: Locale.preferredLanguages)).font(.footnote).foregroundStyle(Color.inkSoft)
                case let .compose(focus):
                    Text(focus.titleResource).font(.headline.weight(.heavy))
                    Text("training.next.compose \(viewModel.workoutMinutes)").font(.footnote).foregroundStyle(Color.inkSoft)
                }
            }
        }
        .accessibilityIdentifier("training.next")
    }

    /// One exercise the coach has a word about: go heavier, or try another exercise for the same muscle.
    private func coachRow(_ note: CoachNote) -> some View {
        let languages = Locale.preferredLanguages
        return HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: isHeavier(note) ? "arrow.up.circle.fill" : "arrow.triangle.swap")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: note.exercise.name.text(preferring: languages)).font(.headline)
                Group {
                    switch note.kind {
                    case let .heavier(advice):
                        Text(advice.text(unit: WeightUnit(locale: .current)))
                    case let .switchTo(other):
                        Text("training.coach.switch \(other.name.text(preferring: languages))")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("training.coach.\(isHeavier(note) ? "heavier" : "switch").\(note.exercise.id.uuidString)")
    }

    private func isHeavier(_ note: CoachNote) -> Bool {
        if case .heavier = note.kind { return true }
        return false
    }

    private func sessionLabel(_ session: WorkoutSession, systemImage: String) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: systemImage).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if let title = viewModel.title(of: session) {
                    Text(verbatim: title.text(preferring: Locale.preferredLanguages)).font(.headline)
                } else {
                    Text("training.session.free").font(.headline)
                }
                Text("training.session.detail \(session.startedAt.formatted(date: .abbreviated, time: .omitted)) \(viewModel.setCount(of: session))")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A name and the number of training days for a new programme of the user's own.
struct NewProgramSheet: View {
    @State private var name = ""
    @State private var days = 3
    private let onCreate: (String, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    init(onCreate: @escaping (String, Int) -> Void) {
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("training.program.name", text: $name)
                        .accessibilityIdentifier("training.program.name")
                    Stepper(value: $days, in: 1...7) {
                        Text("training.program.days \(days)")
                    }
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .navigationTitle("training.program.new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines), days)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
