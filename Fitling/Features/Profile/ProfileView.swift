import SwiftUI
import FitlingCore

struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    /// In state too: the parent builds a new one on every render, and the first one must stay.
    @State private var account: AccountViewModel
    @State private var editingProfile = false
    @State private var editingTargets = false

    init(profile: UserProfile, sync: SyncEngine, account: AccountViewModel) {
        _viewModel = State(initialValue: ProfileViewModel(profile: profile, sync: sync))
        _account = State(initialValue: account)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let profile = viewModel.profile.bodyProfile, viewModel.plan != nil {
                        value("profile.proteinPerKg") {
                            Text("profile.proteinPerKg.value \(profile.goal.proteinPerKg, format: .number.precision(.fractionLength(1)))")
                        }
                    } else {
                        Text("profile.profileInvalid")
                    }
                } header: {
                    // In the header the card keeps its own shape and shadow instead of becoming a row.
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        TargetBuildUp(
                            plan: viewModel.plan, profile: viewModel.profile.bodyProfile, targets: viewModel.profile.targets
                        )
                        // Section headers sit one margin further in than rows; line the card up with the list.
                        .padding(.horizontal, -Spacing.l)
                        if let problem = viewModel.syncProblemKey {
                            Label(LocalizedStringKey(problem), systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                                .font(.footnote)
                        }
                        if viewModel.profile.targetsAreManual {
                            Text("profile.targets.manual")
                                .font(.footnote)
                        }
                        if viewModel.plan?.floorApplied == true, !viewModel.profile.targetsAreManual {
                            Label("targets.floor", systemImage: "arrow.up.to.line")
                                .font(.footnote)
                        }
                        ForEach(viewModel.warnings, id: \.self) { warning in
                            Label(warning.messageKey, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                        }
                    }
                    .foregroundStyle(Color.ink)
                    .textCase(nil)
                    .padding(.bottom, Spacing.s)
                } footer: {
                    Text("profile.rounding").footerStyle()
                }
                .listRowBackground(Color.card)

                Section {
                    NavigationLink("account.title") {
                        AccountView(viewModel: account)
                    }
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .navigationTitle("profile.title")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("profile.adjust") {
                        Button("profile.edit") { editingProfile = true }
                        Button("profile.editTargets") { editingTargets = true }
                    }
                    .accessibilityIdentifier("profile.adjust")
                }
            }
            .sheet(isPresented: $editingProfile) {
                EditProfileView(viewModel: viewModel)
            }
            .sheet(isPresented: $editingTargets) {
                EditTargetsView(viewModel: viewModel)
            }
        }
    }

    /// Numbers stay strict in the rounded world: heavy, tabular, in ink.
    private func value(_ label: LocalizedStringKey, _ content: () -> Text) -> some View {
        LabeledContent(label) {
            content()
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(Color.ink)
        }
    }

    private func energy(_ kcal: Double) -> String {
        Measurement(value: kcal.rounded(), unit: UnitEnergy.kilocalories)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }
}

/// How the daily target is built, as steps that grow towards it: resting metabolism, times how
/// active you are, times your goal. Every number on the way is shown, then the macros as blocks.
private struct TargetBuildUp: View {
    let plan: EnergyPlan?
    let profile: BodyProfile?
    let targets: NutritionTargets
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let plan, let profile {
                let largest = max(plan.bmr, plan.tdee, Double(targets.kcal), 1)
                step("profile.bmr", kcal: plan.bmr, share: plan.bmr / largest)
                factor(Text("profile.buildUp.activity \(profile.activityLevel.multiplier.formatted(.number.precision(.fractionLength(0...3))))"))
                step("profile.tdee", kcal: plan.tdee, share: plan.tdee / largest)
                factor(Text("profile.buildUp.goal \(profile.goal.kcalFactor.formatted(.percent))"))
                target(share: Double(targets.kcal) / largest)
            } else {
                target(share: 1)
            }
            MacroBlocks(targets: targets)
                .padding(.top, Spacing.s)
        }
        .foregroundStyle(Color.ink)
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.card)
                .shadow(color: Color.cardShadow, radius: 12, y: 4)
        }
    }

    /// A step as wide as its share of the largest number, so the steps rise towards the target.
    /// At the accessibility sizes every step takes the full width.
    private func step(_ key: LocalizedStringKey, kcal: Double, share: Double) -> some View {
        StepWidth(fraction: dynamicTypeSize.isAccessibilitySize ? 1 : max(share, 0.62)) {
            labelled(Text(key), value: Text(energy(kcal)), valueFont: .title3.weight(.heavy))
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                .frame(maxWidth: .infinity, minHeight: Radius.ribbon * 2, alignment: .leading)
                .background(Color.track, in: RoundedRectangle(cornerRadius: Radius.ribbon, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }

    private func target(share: Double) -> some View {
        StepWidth(fraction: dynamicTypeSize.isAccessibilitySize ? 1 : max(share, 0.62)) {
            labelled(Text("profile.buildUp.target"), value: Text(energy(Double(targets.kcal))), valueFont: .title.weight(.heavy))
                .foregroundStyle(Color.card)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.m)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(Color.ink, in: RoundedRectangle(cornerRadius: Radius.ribbon, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }

    private func factor(_ text: Text) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: "arrow.turn.down.right")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.inkSoft)
        .padding(.leading, Spacing.l)
    }

    private func labelled(_ label: Text, value: Text, valueFont: Font) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.s))
        return layout {
            label
                .font(.subheadline.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: Spacing.s)
            }
            value
                .font(valueFont)
                .monospacedDigit()
        }
    }

    private func energy(_ kcal: Double) -> String {
        Measurement(value: kcal.rounded(), unit: UnitEnergy.kilocalories)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }
}

/// Gives its content a fraction of the offered width, from the leading edge.
private struct StepWidth: Layout {
    let fraction: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        guard let width = proposal.width else { return child.sizeThatFits(proposal) }
        let size = child.sizeThatFits(ProposedViewSize(width: width * fraction, height: nil))
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width * fraction, height: bounds.height))
    }
}
