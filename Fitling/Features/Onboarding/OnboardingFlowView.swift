import SwiftUI
import FitlingCore

struct OnboardingFlowView: View {
    typealias Step = OnboardingViewModel.Step

    @State private var viewModel: OnboardingViewModel
    /// Every step after consent is pushed, so the system back button and edge swipe work.
    @State private var path: [Step] = []
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
        NavigationStack(path: $path) {
            screen(for: .consent)
                .navigationDestination(for: Step.self) { step in
                    screen(for: step)
                }
        }
        .onChange(of: path) { _, newPath in
            viewModel.returnTo(newPath.last ?? .consent)
        }
        .alert("error.server", isPresented: $saveFailed) {
            Button("common.ok", role: .cancel) {}
        }
    }

    private func screen(for step: Step) -> some View {
        List { content(for: step) }
            .foregroundStyle(Color.ink)
            .groundBackground()
            // On the list only: on the whole screen it would replace the identifier of the button below.
            .accessibilityIdentifier("onboarding.step.\(String(describing: step))")
            .navigationTitle(title(for: step))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { bottomBar(for: step) }
    }

    private func title(for step: Step) -> LocalizedStringKey {
        switch step {
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
    private func content(for step: Step) -> some View {
        switch step {
        case .consent:
            Section {
                Text("consent.body")
            }
            .listRowBackground(Color.card)
            Section {
                Toggle("consent.agree", isOn: $viewModel.consentGiven)
                    .tint(Color.sprout)
                    .accessibilityIdentifier("consent.agree")
            }
            .listRowBackground(Color.card)
        case .birthDate:
            Section {
                DatePicker(
                    "onboarding.birthDate.label",
                    selection: $viewModel.birthDate,
                    in: viewModel.earliestBirthDate...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.calendar, BirthDateCalendar.calendar)
                .environment(\.timeZone, BirthDateCalendar.calendar.timeZone)
            } footer: {
                Text("onboarding.birthDate.footer").footerStyle()
            }
            .listRowBackground(Color.card)
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
                Text("onboarding.sex.footer").footerStyle()
            }
            .listRowBackground(Color.card)
        case .height:
            Section {
                if viewModel.usesMetric {
                    numberRow("onboarding.height.field", value: centimetres, unit: UnitLength.centimeters.symbol, identifier: "input.height")
                } else {
                    numberRow("onboarding.height.feet", value: feetBinding, unit: UnitLength.feet.symbol, identifier: "input.feet")
                    numberRow("onboarding.height.inches", value: inchesBinding, unit: UnitLength.inches.symbol, identifier: "input.inches")
                }
            }
            .listRowBackground(Color.card)
        case .weight:
            Section {
                numberRow(
                    "onboarding.weight.field",
                    value: weight,
                    unit: (viewModel.usesMetric ? UnitMass.kilograms : UnitMass.pounds).symbol,
                    identifier: "input.weight"
                )
            }
            .listRowBackground(Color.card)
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
            .listRowBackground(Color.card)
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
            .listRowBackground(Color.card)
        case .result:
            if let calculation = viewModel.calculation {
                Section {
                    if calculation.isBelowSafeMinimum {
                        Label("targets.warning.low", systemImage: "exclamationmark.triangle")
                    }
                    Text("onboarding.result.footer")
                } header: {
                    // In the header the card keeps its own shape and shadow instead of becoming a row.
                    TargetsCard(targets: calculation.targets)
                        .textCase(nil)
                        // Section headers sit one margin further in than rows; line the fields up with the list.
                        .padding(.horizontal, -Spacing.l)
                        .padding(.bottom, Spacing.s)
                }
                .listRowBackground(Color.card)
            }
        }
    }

    private func choice(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
            Text(detail).font(.footnote).foregroundStyle(Color.inkSoft)
        }
    }

    private func numberRow(_ label: LocalizedStringKey, value: Binding<Double?>, unit: String, identifier: String) -> some View {
        HStack {
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
                .accessibilityIdentifier(identifier)
            Text(verbatim: unit).foregroundStyle(Color.inkSoft)
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

    private func bottomBar(for step: Step) -> some View {
        VStack(spacing: Spacing.m) {
            OnboardingProgress(current: step)
            if step == .birthDate && viewModel.isUnderage {
                Text("onboarding.underage.body")
                    .font(.footnote)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Task { await onDeleteAccount() }
                } label: {
                    Text("onboarding.underage.delete")
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button {
                    advance(from: step)
                } label: {
                    Text(step == .result ? LocalizedStringKey("onboarding.finish") : "onboarding.continue")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canContinue(at: step))
                .accessibilityIdentifier("onboarding.continue.\(String(describing: step))")
            }
        }
        .padding(Spacing.l)
        .background(Color.ground)
    }

    private func advance(from step: Step) {
        guard viewModel.step == step else { return }
        if step == .result {
            finish()
            return
        }
        viewModel.next()
        if viewModel.step != step {
            path.append(viewModel.step)
        }
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

/// One pill per step: done and current steps are ink, the rest the track colour.
struct OnboardingProgress: View {
    let current: OnboardingViewModel.Step

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= current.rawValue ? Color.ink : Color.track)
                    .frame(height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("onboarding.progress \(current.rawValue + 1) \(OnboardingViewModel.Step.allCases.count)"))
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
