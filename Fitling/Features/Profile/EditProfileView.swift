import SwiftUI
import FitlingCore

struct EditProfileView: View {
    let viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var birthDay: Day
    @State private var sex: Sex
    @State private var input: BodyInput
    @State private var activityLevel: ActivityLevel
    @State private var goal: Goal
    @State private var askRecalculate = false

    init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
        let profile = viewModel.profile
        let body = profile.bodyProfile
        _birthDay = State(initialValue: Day(isoString: profile.birthDate) ?? BirthDayPicking.day(30, yearsBefore: viewModel.today))
        _sex = State(initialValue: body?.sex ?? .other)
        _input = State(initialValue: BodyInput(usesMetric: Locale.current.measurementSystem == .metric, heightCm: profile.heightCm, weightKg: profile.weightKg))
        _activityLevel = State(initialValue: body?.activityLevel ?? .moderate)
        _goal = State(initialValue: body?.goal ?? .maintain)
    }

    /// Nil while a value is missing or outside what the database accepts.
    private var edited: BodyProfile? {
        guard input.isValid, let heightCm = input.heightCm, let weightKg = input.weightKg,
              isValidBirthDay(birthDay, on: viewModel.today) else { return nil }
        return BodyProfile(birthDay: birthDay, sex: sex, heightCm: heightCm, weightKg: weightKg, activityLevel: activityLevel, goal: goal)
    }

    private var birthDate: Binding<Date> {
        Binding(
            get: { BirthDayPicking.date(for: birthDay) },
            set: { birthDay = BirthDayPicking.day(for: $0) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "onboarding.birthDate.label",
                        selection: birthDate,
                        in: BirthDayPicking.date(for: Limits.earliestBirthDay)...BirthDayPicking.date(for: viewModel.today),
                        displayedComponents: .date
                    )
                    .environment(\.calendar, BirthDayPicking.calendar)
                    .environment(\.timeZone, BirthDayPicking.calendar.timeZone)
                    Picker("onboarding.sex.title", selection: $sex) {
                        Text("onboarding.sex.male").tag(Sex.male)
                        Text("onboarding.sex.female").tag(Sex.female)
                        Text("onboarding.sex.other").tag(Sex.other)
                    }
                }
                .listRowBackground(Color.card)
                Section {
                    if input.usesMetric {
                        numberRow("onboarding.height.field", value: $input.centimetres, unit: UnitLength.centimeters.symbol)
                    } else {
                        numberRow("onboarding.height.feet", value: $input.feet, unit: UnitLength.feet.symbol)
                        numberRow("onboarding.height.inches", value: $input.inches, unit: UnitLength.inches.symbol)
                    }
                    numberRow("onboarding.weight.field", value: $input.weight, unit: input.massUnit.symbol)
                }
                .listRowBackground(Color.card)
                Section {
                    Picker("onboarding.activity.title", selection: $activityLevel) {
                        ForEach(ActivityLevel.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                    }
                    Picker("onboarding.goal.title", selection: $goal) {
                        ForEach(Goal.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                    }
                } footer: {
                    if edited == nil { Text("profile.profileInvalid").foregroundStyle(Color.ink) }
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .navigationTitle("profile.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("profile.save") { save() }
                        .disabled(edited == nil)
                }
            }
            .confirmationDialog("profile.recalculate.title", isPresented: $askRecalculate, titleVisibility: .visible) {
                Button("profile.recalculate.confirm") {
                    viewModel.recalculateTargets()
                    dismiss()
                }
                Button("profile.recalculate.keep", role: .cancel) { dismiss() }
            }
        }
    }

    private func numberRow(_ label: LocalizedStringKey, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
            Text(verbatim: unit).foregroundStyle(Color.inkSoft)
        }
    }

    private func save() {
        guard let edited else { return }
        if viewModel.saveProfile(edited) == .askRecalculate {
            askRecalculate = true
        } else {
            dismiss()
        }
    }
}

struct EditTargetsView: View {
    let viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var kcal: Int?
    @State private var protein: Int?
    @State private var carbs: Int?
    @State private var fat: Int?
    @State private var showsRangeError = false

    init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
        let targets = viewModel.profile.targets
        _kcal = State(initialValue: targets.kcal)
        _protein = State(initialValue: targets.proteinG)
        _carbs = State(initialValue: targets.carbsG)
        _fat = State(initialValue: targets.fatG)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("profile.targets.kcal", value: $kcal, format: .number).keyboardType(.numberPad)
                    TextField("profile.targets.protein", value: $protein, format: .number).keyboardType(.numberPad)
                    TextField("profile.targets.carbs", value: $carbs, format: .number).keyboardType(.numberPad)
                    TextField("profile.targets.fat", value: $fat, format: .number).keyboardType(.numberPad)
                } footer: {
                    if showsRangeError { Text("profile.targets.outOfRange").foregroundStyle(Color.ink) }
                }
                .listRowBackground(Color.card)
                Section {
                    Button("profile.recalculate.confirm") {
                        viewModel.recalculateTargets()
                        dismiss()
                    }
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .navigationTitle("profile.editTargets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("profile.save") { save() }
                }
            }
        }
    }

    private func save() {
        guard let kcal, let protein, let carbs, let fat else {
            showsRangeError = true
            return
        }
        do throws(ProfileViewModel.TargetsError) {
            try viewModel.saveTargets(NutritionTargets(kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat))
            dismiss()
        } catch {
            showsRangeError = true
        }
    }
}
