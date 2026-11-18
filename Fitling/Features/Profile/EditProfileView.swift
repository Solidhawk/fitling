import SwiftUI
import FitlingCore

struct EditProfileView: View {
    let viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var birthDate: Date
    @State private var sex: Sex
    @State private var height: Double?
    @State private var weight: Double?
    @State private var activityLevel: ActivityLevel
    @State private var goal: Goal
    @State private var askRecalculate = false
    private let usesMetric = Locale.current.measurementSystem == .metric

    init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
        let body = viewModel.profile.bodyProfile
        let metric = Locale.current.measurementSystem == .metric
        _birthDate = State(initialValue: body.birthDate)
        _sex = State(initialValue: body.sex)
        _height = State(initialValue: Measurement(value: body.heightCm, unit: UnitLength.centimeters).converted(to: metric ? .centimeters : .inches).value)
        _weight = State(initialValue: Measurement(value: body.weightKg, unit: UnitMass.kilograms).converted(to: metric ? .kilograms : .pounds).value)
        _activityLevel = State(initialValue: body.activityLevel)
        _goal = State(initialValue: body.goal)
    }

    private var lengthUnit: UnitLength { usesMetric ? .centimeters : .inches }
    private var massUnit: UnitMass { usesMetric ? .kilograms : .pounds }

    /// Nil while a value is missing or outside what the database accepts.
    private var edited: BodyProfile? {
        guard let height, let weight else { return nil }
        let heightCm = (Measurement(value: height, unit: lengthUnit).converted(to: .centimeters).value * 10).rounded() / 10
        let weightKg = (Measurement(value: weight, unit: massUnit).converted(to: .kilograms).value * 10).rounded() / 10
        let calendar = BirthDateCalendar.calendar
        guard Limits.heightCm.contains(heightCm), Limits.weightKg.contains(weightKg),
              isValidBirthDate(birthDate, on: Date(), calendar: calendar) else { return nil }
        return BodyProfile(
            birthDate: calendar.startOfDay(for: birthDate),
            sex: sex, heightCm: heightCm, weightKg: weightKg, activityLevel: activityLevel, goal: goal
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("onboarding.birthDate.label", selection: $birthDate, in: (BirthDateCalendar.calendar.date(from: Limits.earliestBirthDate) ?? .distantPast)...Date(), displayedComponents: .date)
                        .environment(\.calendar, BirthDateCalendar.calendar)
                        .environment(\.timeZone, BirthDateCalendar.calendar.timeZone)
                    Picker("onboarding.sex.title", selection: $sex) {
                        Text("onboarding.sex.male").tag(Sex.male)
                        Text("onboarding.sex.female").tag(Sex.female)
                        Text("onboarding.sex.other").tag(Sex.other)
                    }
                }
                .listRowBackground(Color.card)
                Section {
                    numberRow("onboarding.height.field", value: $height, unit: lengthUnit.symbol)
                    numberRow("onboarding.weight.field", value: $weight, unit: massUnit.symbol)
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
                    if edited == nil { Text("profile.profileInvalid") }
                }
                .listRowBackground(Color.card)
            }
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
                    if showsRangeError { Text("profile.targets.outOfRange") }
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
