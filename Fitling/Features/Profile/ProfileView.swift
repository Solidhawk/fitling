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
                    TargetsComposition(targets: viewModel.profile.targets)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    if viewModel.profile.targetsAreManual {
                        Text("profile.targets.manual")
                    }
                }

                if viewModel.isBelowSafeMinimum {
                    Section {
                        Label("targets.warning.low", systemImage: "exclamationmark.triangle")
                    }
                }

                Section("profile.howCalculated") {
                    LabeledContent("profile.bmr") { Text(energy(viewModel.calculation.bmr)) }
                    LabeledContent("profile.tdee") { Text(energy(viewModel.calculation.tdee)) }
                    LabeledContent("profile.activityFactor") {
                        Text(viewModel.profile.bodyProfile.activityLevel.multiplier, format: .number.precision(.fractionLength(0...3)))
                    }
                    LabeledContent("profile.goalFactor") {
                        Text(viewModel.profile.bodyProfile.goal.kcalFactor, format: .percent)
                    }
                    LabeledContent("profile.proteinPerKg") {
                        Text("profile.proteinPerKg.value \(viewModel.profile.bodyProfile.goal.proteinPerKg, format: .number.precision(.fractionLength(1)))")
                    }
                }

                Section {
                    Button("profile.edit") { editingProfile = true }
                    Button("profile.editTargets") { editingTargets = true }
                    NavigationLink("account.title") {
                        AccountView(viewModel: account)
                    }
                }
            }
            .navigationTitle("profile.title")
            .sheet(isPresented: $editingProfile) {
                EditProfileView(viewModel: viewModel)
            }
            .sheet(isPresented: $editingTargets) {
                EditTargetsView(viewModel: viewModel)
            }
        }
    }

    private func energy(_ kcal: Double) -> String {
        Measurement(value: kcal.rounded(), unit: UnitEnergy.kilocalories)
            .formatted(.measurement(width: .abbreviated, usage: .food))
    }
}
