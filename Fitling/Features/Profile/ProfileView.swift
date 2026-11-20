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
                    if let plan = viewModel.plan, let profile = viewModel.profile.bodyProfile {
                        value("profile.bmr") { Text(energy(plan.bmr)) }
                        value("profile.tdee") { Text(energy(plan.tdee)) }
                        value("profile.activityFactor") {
                            Text(profile.activityLevel.multiplier, format: .number.precision(.fractionLength(0...3)))
                        }
                        value("profile.goalFactor") {
                            Text(profile.goal.kcalFactor, format: .percent)
                        }
                        value("profile.proteinPerKg") {
                            Text("profile.proteinPerKg.value \(profile.goal.proteinPerKg, format: .number.precision(.fractionLength(1)))")
                        }
                    } else {
                        Text("profile.profileInvalid")
                    }
                } header: {
                    // In the header the card keeps its own shape and shadow instead of becoming a row.
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        TargetsCard(targets: viewModel.profile.targets)
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
                        Text("profile.howCalculated")
                            .font(.headline.weight(.heavy))
                            .padding(.top, Spacing.m)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .foregroundStyle(Color.ink)
                    .textCase(nil)
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
