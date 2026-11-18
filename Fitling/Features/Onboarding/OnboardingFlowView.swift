import SwiftUI
import FitlingCore

struct OnboardingFlowView: View {
    @State private var viewModel: OnboardingViewModel
    @State private var feet: Double?
    @State private var inches: Double?
    @State private var saveFailed = false
    private let onFinished: (UserProfile) async -> Void
    private let onDeleteAccount: () async -> Void

    init(
        viewModel: OnboardingViewModel,
        onFinished: @escaping (UserProfile) async -> Void,
        onDeleteAccount: @escaping () async -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onFinished = onFinished
        self.onDeleteAccount = onDeleteAccount
    }

    var body: some View {
        NavigationStack {
            Form { content }
                // On the form only: on the whole view it would replace the identifier of the button below.
                .accessibilityIdentifier("onboarding.step.\(String(describing: viewModel.step))")
                .navigationTitle(title)
                .toolbar {
                    if viewModel.step != .consent {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("onboarding.back") { viewModel.back() }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) { bottomBar }
                .alert("error.server", isPresented: $saveFailed) {
                    Button("common.ok", role: .cancel) {}
                }
        }
    }

    private var title: LocalizedStringKey {
        switch viewModel.step {
        case .consent: "consent.title"
        case .birthDate: "onboarding.birthDate.title"
        case .sex: "onboarding.sex.title"
        case .height: "onboarding.height.title"
        case .weight: "onboarding.weight.title"
        case .activity: "onboarding.activity.title"
        case .goal: "onboarding.goal.title"
        case .result: "onboarding.result.title"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .consent:
            Section {
                Text("consent.body")
            }
            Section {
                Toggle("consent.agree", isOn: $viewModel.consentGiven)
                    .accessibilityIdentifier("consent.agree")
            }
        case .birthDate:
            Section {
                DatePicker("onboarding.birthDate.label", selection: $viewModel.birthDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.calendar, BirthDateCalendar.calendar)
                    .environment(\.timeZone, BirthDateCalendar.calendar.timeZone)
            } footer: {
                Text("onboarding.birthDate.footer")
            }
        case .sex:
            Section {
                Picker("onboarding.sex.title", selection: $viewModel.sex) {
                    Text("onboarding.sex.male").tag(Sex?.some(.male))
                    Text("onboarding.sex.female").tag(Sex?.some(.female))
                    Text("onboarding.sex.other").tag(Sex?.some(.other))
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("onboarding.sex.footer")
            }
        case .height:
            Section {
                if viewModel.usesMetric {
                    numberRow("onboarding.height.field", value: centimetres, unit: UnitLength.centimeters.symbol, identifier: "input.height")
                } else {
                    numberRow("onboarding.height.feet", value: feetBinding, unit: UnitLength.feet.symbol, identifier: "input.feet")
                    numberRow("onboarding.height.inches", value: inchesBinding, unit: UnitLength.inches.symbol, identifier: "input.inches")
                }
            }
        case .weight:
            Section {
                numberRow("onboarding.weight.field", value: weight, unit: (viewModel.usesMetric ? UnitMass.kilograms : UnitMass.pounds).symbol, identifier: "input.weight")
            }
        case .activity:
            Section {
                Picker("onboarding.activity.title", selection: $viewModel.activityLevel) {
                    ForEach(ActivityLevel.allCases, id: \.self) { level in
                        choice(level.titleKey, detail: level.detailKey).tag(ActivityLevel?.some(level))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        case .goal:
            Section {
                Picker("onboarding.goal.title", selection: $viewModel.goal) {
                    ForEach(Goal.allCases, id: \.self) { goal in
                        choice(goal.titleKey, detail: goal.detailKey).tag(Goal?.some(goal))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        case .result:
            if let calculation = viewModel.calculation {
                Section {
                    if calculation.isBelowSafeMinimum {
                        Label("targets.warning.low", systemImage: "exclamationmark.triangle")
                    }
                    Text("onboarding.result.footer")
                } header: {
                    // A section header is not clipped to the rounded row shape, so the De Stijl
                    // fields keep their square corners.
                    TargetsComposition(targets: calculation.targets)
                        .textCase(nil)
                        .padding(.bottom, Spacing.s)
                }
            }
        }
    }

    private func choice(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func numberRow(_ label: LocalizedStringKey, value: Binding<Double?>, unit: String, identifier: String) -> some View {
        HStack {
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier(identifier)
            Text(verbatim: unit).foregroundStyle(.secondary)
        }
    }

    private var centimetres: Binding<Double?> {
        Binding(
            get: { viewModel.heightInput?.converted(to: .centimeters).value },
            set: { viewModel.heightInput = $0.map { Measurement(value: $0, unit: .centimeters) } }
        )
    }

    private var feetBinding: Binding<Double?> {
        Binding(get: { feet }, set: { feet = $0; updateImperialHeight() })
    }

    private var inchesBinding: Binding<Double?> {
        Binding(get: { inches }, set: { inches = $0; updateImperialHeight() })
    }

    private func updateImperialHeight() {
        viewModel.heightInput = feet.map { Measurement(value: $0 * 12 + (inches ?? 0), unit: .inches) }
    }

    private var weight: Binding<Double?> {
        let unit: UnitMass = viewModel.usesMetric ? .kilograms : .pounds
        return Binding(
            get: { viewModel.weightInput?.converted(to: unit).value },
            set: { viewModel.weightInput = $0.map { Measurement(value: $0, unit: unit) } }
        )
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: Spacing.s) {
            if viewModel.step == .birthDate && viewModel.isUnderage {
                Text("onboarding.underage.body")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive) {
                    Task { await onDeleteAccount() }
                } label: {
                    Text("onboarding.underage.delete").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    if viewModel.step == .result {
                        finish()
                    } else {
                        viewModel.next()
                    }
                } label: {
                    Text(viewModel.step == .result ? LocalizedStringKey("onboarding.finish") : "onboarding.continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canContinue)
                .accessibilityIdentifier("onboarding.continue")
            }
        }
        .padding(Spacing.l)
        .background(.bar)
    }

    private func finish() {
        do {
            let profile = try viewModel.finish()
            Task { await onFinished(profile) }
        } catch {
            saveFailed = true
        }
    }
}

extension ActivityLevel {
    var titleKey: LocalizedStringKey {
        switch self {
        case .sedentary: "onboarding.activity.sedentary"
        case .light: "onboarding.activity.light"
        case .moderate: "onboarding.activity.moderate"
        case .active: "onboarding.activity.active"
        case .veryActive: "onboarding.activity.veryActive"
        }
    }

    var detailKey: LocalizedStringKey {
        switch self {
        case .sedentary: "onboarding.activity.sedentary.detail"
        case .light: "onboarding.activity.light.detail"
        case .moderate: "onboarding.activity.moderate.detail"
        case .active: "onboarding.activity.active.detail"
        case .veryActive: "onboarding.activity.veryActive.detail"
        }
    }
}

extension Goal {
    var titleKey: LocalizedStringKey {
        switch self {
        case .lose: "onboarding.goal.lose"
        case .buildMuscle: "onboarding.goal.buildMuscle"
        case .maintain: "onboarding.goal.maintain"
        case .recomp: "onboarding.goal.recomp"
        }
    }

    var detailKey: LocalizedStringKey {
        switch self {
        case .lose: "onboarding.goal.lose.detail"
        case .buildMuscle: "onboarding.goal.buildMuscle.detail"
        case .maintain: "onboarding.goal.maintain.detail"
        case .recomp: "onboarding.goal.recomp.detail"
        }
    }
}
