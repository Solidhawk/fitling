import SwiftUI
import FitlingCore

struct ProfileView: View {
    @State private var viewModel: ProfileViewModel
    private let account: AccountViewModel
    @State private var editingProfile = false
    @State private var editingTargets = false

    init(profile: UserProfile, sync: ProfileSync, account: AccountViewModel) {
        _viewModel = State(initialValue: ProfileViewModel(profile: profile, sync: sync))
        self.account = account
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    value("profile.bmr") { Text(energy(viewModel.calculation.bmr)) }
                    value("profile.tdee") { Text(energy(viewModel.calculation.tdee)) }
                    value("profile.activityFactor") {
                        Text(viewModel.profile.bodyProfile.activityLevel.multiplier, format: .number.precision(.fractionLength(0...3)))
                    }
                    value("profile.goalFactor") {
                        Text(viewModel.profile.bodyProfile.goal.kcalFactor, format: .percent)
                    }
                    value("profile.proteinPerKg") {
                        Text("profile.proteinPerKg.value \(viewModel.profile.bodyProfile.goal.proteinPerKg, format: .number.precision(.fractionLength(1)))")
                    }
                } header: {
                    // A section header is not clipped to the rounded row shape, so the De Stijl
                    // fields keep their square corners.
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        TargetsComposition(targets: viewModel.profile.targets)
                            // Section headers sit one margin further in than rows; line the fields up with the list.
                            .padding(.horizontal, -Spacing.l)
                        if let problem = viewModel.syncProblemKey {
                            Label(LocalizedStringKey(problem), systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                                .font(.footnote)
                                .foregroundStyle(Color.ink)
                        }
                        if viewModel.profile.targetsAreManual {
                            Text("profile.targets.manual")
                                .font(.footnote)
                        }
                        if viewModel.isBelowSafeMinimum {
                            Label("targets.warning.low", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(Color.ink)
                        }
                        Text("profile.howCalculated")
                            .textCase(.uppercase)
                            .padding(.top, Spacing.s)
                    }
                    .textCase(nil)
                } footer: {
                    Text("profile.rounding")
                }
                .listRowBackground(Color.paper)

                Section {
                    NavigationLink("account.title") {
                        AccountView(viewModel: account)
                    }
                }
                .listRowBackground(Color.paper)
            }
            .paperGround()
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

    /// Numbers are part of the composition's language: heavy, tabular, in ink.
    private func value(_ label: LocalizedStringKey, _ content: () -> Text) -> some View {
        LabeledContent(label) {
            content()
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Color.ink)
        }
    }

    private func energy(_ kcal: Double) -> String {
        Measurement(value: kcal.rounded(), unit: UnitEnergy.kilocalories)
            .formatted(.measurement(width: .abbreviated, usage: .food))
    }
}
