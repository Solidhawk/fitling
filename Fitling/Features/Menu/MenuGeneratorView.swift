import SwiftUI
import FitlingCore

/// Making a menu: how many days from today, for which goal, which meals and what to leave out; then
/// one tap. It opens with the choices of the last menu.
struct MenuGeneratorView: View {
    let viewModel: MenuViewModel
    @State private var options: MenuOptions
    @State private var preferences: MenuPreferences?
    @Environment(\.dismiss) private var dismiss

    init(viewModel: MenuViewModel) {
        self.viewModel = viewModel
        _options = State(initialValue: viewModel.options)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper(value: $options.days, in: 1...MenuStore.menuDays) {
                        Text("menu.generator.days \(options.days)")
                            .fontWeight(.heavy)
                            .monospacedDigit()
                    }
                    .accessibilityIdentifier("menu.generator.days")
                } header: {
                    Text("menu.generator.days.title")
                } footer: {
                    Text("menu.generator.days.footer").footerStyle()
                }
                .listRowBackground(Color.card)

                Section {
                    Picker("menu.generator.goal", selection: $options.goal) {
                        goalRow(nil).tag(Goal?.none)
                        ForEach(Goal.allCases, id: \.self) { goal in
                            goalRow(goal).tag(Goal?.some(goal))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .tint(Color.ink)
                } header: {
                    Text("menu.generator.goal")
                }
                .listRowBackground(Color.card)

                if let preferences {
                    MenuPreferenceSections(store: viewModel.store, preferences: preferences)
                }
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .safeAreaInset(edge: .bottom) {
                Button {
                    viewModel.generate(options)
                    dismiss()
                } label: {
                    Text("menu.generator.make \(options.days)")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("menu.generator.make")
                .padding(Spacing.l)
                .background(Color.ground)
            }
            .navigationTitle("menu.generator.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .onAppear { preferences = viewModel.store.preferences() }
        }
    }

    /// A goal with the kcal per day the menu would plan for it.
    private func goalRow(_ goal: Goal?) -> some View {
        let targets = viewModel.targets(for: goal)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(goal?.titleKey ?? "menu.generator.goal.daily")
            Text("menu.generator.goal.kcal \(targets.kcal)")
                .font(.footnote)
                .foregroundStyle(Color.inkSoft)
                .monospacedDigit()
        }
    }
}
