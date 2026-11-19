import SwiftUI

struct RootView: View {
    @State private var viewModel: RootViewModel
    @State private var network = NetworkMonitor()
    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: RootViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .task(id: viewModel.auth.state) { await viewModel.refresh() }
            .onOpenURL { url in
                Task { await viewModel.open(url) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await viewModel.refresh() } }
            }
            .onChange(of: network.isConnected) { _, isConnected in
                if isConnected { Task { await viewModel.refresh() } }
            }
            .sheet(isPresented: $viewModel.showsPasswordReset) {
                ResetPasswordView(auth: viewModel.auth)
            }
            .sheet(item: Binding(get: { viewModel.underageDeletion }, set: { if $0 == nil { viewModel.dismissUnderageDeletion() } })) { _ in
                UnderageDeletionSheet(viewModel: accountViewModel())
            }
            .alert(
                "auth.link.title",
                isPresented: Binding(get: { viewModel.linkMessageKey != nil }, set: { if !$0 { viewModel.clearLinkMessage() } })
            ) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text(LocalizedStringKey(viewModel.linkMessageKey ?? "error.server"))
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.screen {
        case .loading:
            ProgressView()
                .accessibilityLabel(Text("common.loading"))
                .accessibilityIdentifier("root.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.ground)
        case .welcome:
            WelcomeView(auth: viewModel.auth)
        case let .verifyEmail(email):
            VerifyEmailView(auth: viewModel.auth, email: email)
                .id(email)
        case .needsConnection:
            NeedsConnectionView {
                Task { await viewModel.refresh() }
            }
        case let .onboarding(userID):
            OnboardingFlowView(
                viewModel: OnboardingViewModel(userID: userID, context: viewModel.sync.context, locale: .current),
                onFinished: { profile in await viewModel.onboardingFinished(profile) },
                onDeleteAccount: { viewModel.requestUnderageDeletion(userID: userID) }
            )
            .id(userID)
        case let .partnerSetup(userID):
            PartnerSetupView(viewModel: PartnerSetupViewModel(userID: userID, context: viewModel.sync.context)) { creature in
                await viewModel.partnerChosen(creature)
            }
            .id(userID)
        case let .home(userID):
            if let profile = viewModel.sync.context.profile(of: userID) {
                HomeView(
                    profile: profile, sync: viewModel.sync, food: viewModel.food, reminders: viewModel.reminders,
                    health: viewModel.health, account: accountViewModel()
                )
                    .id(userID)
            } else {
                // Only between a wipe and the refresh that follows it; the refresh picks the screen.
                ProgressView()
                    .accessibilityLabel(Text("common.loading"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.ground)
                    .task { await viewModel.refresh() }
            }
        }
    }

    private func accountViewModel() -> AccountViewModel {
        var usesApple = false
        if case let .signedIn(_, apple) = viewModel.auth.state { usesApple = apple }
        return AccountViewModel(auth: viewModel.auth, sync: viewModel.sync, usesApple: usesApple)
    }
}

struct NeedsConnectionView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("common.connection.title", systemImage: "wifi.slash")
        } description: {
            Text("common.connection.body")
        } actions: {
            Button("common.connection.retry", action: retry)
                .buttonStyle(SecondaryButtonStyle())
        }
        .foregroundStyle(Color.ink)
        .background(Color.ground)
    }
}

/// The account an under-18 user is about to delete from onboarding.
struct AccountDeletion: Identifiable, Equatable {
    let id: UUID
}

/// Keeps one AccountViewModel for the whole sheet, so a re-render of RootView cannot reset it
/// mid-request. RootViewModel closes the sheet once the account is gone.
struct UnderageDeletionSheet: View {
    @State private var viewModel: AccountViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: AccountViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            DeleteAccountView(viewModel: viewModel)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel") { dismiss() }
                    }
                }
        }
    }
}
