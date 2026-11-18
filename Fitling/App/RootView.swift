import SwiftData
import SwiftUI

struct RootView: View {
    @State private var viewModel: RootViewModel
    @State private var network = NetworkMonitor()
    @State private var deletingUnderageAccount: AccountDeletion?
    @Environment(\.scenePhase) private var scenePhase
    private let context: ModelContext

    init(viewModel: RootViewModel, context: ModelContext) {
        _viewModel = State(initialValue: viewModel)
        self.context = context
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
            .sheet(item: $deletingUnderageAccount) { deletion in
                NavigationStack {
                    DeleteAccountView(viewModel: accountViewModel(userID: deletion.id))
                }
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
                .background(Color.paper)
        case .welcome:
            WelcomeView(auth: viewModel.auth)
        case let .verifyEmail(email):
            VerifyEmailView(auth: viewModel.auth, email: email)
        case .needsConnection:
            NeedsConnectionView {
                Task { await viewModel.refresh() }
            }
        case let .onboarding(userID):
            OnboardingFlowView(
                viewModel: OnboardingViewModel(userID: userID, context: context, locale: .current),
                onFinished: { profile in await viewModel.onboardingFinished(profile) },
                onDeleteAccount: { deletingUnderageAccount = AccountDeletion(id: userID) }
            )
            .id(userID)
        case let .home(userID):
            if let profile = viewModel.sync.localProfile(userID: userID) {
                ProfileView(profile: profile, sync: viewModel.sync, account: accountViewModel(userID: userID))
                    .id(userID)
            } else {
                NeedsConnectionView {
                    Task { await viewModel.refresh() }
                }
            }
        }
    }

    private func accountViewModel(userID: UUID) -> AccountViewModel {
        var usesApple = false
        if case let .signedIn(_, apple) = viewModel.auth.state { usesApple = apple }
        return AccountViewModel(auth: viewModel.auth, sync: viewModel.sync, userID: userID, usesApple: usesApple)
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
                .buttonStyle(.bordered)
        }
        .background(Color.paper)
    }
}

/// The account an under-18 user is about to delete from onboarding.
struct AccountDeletion: Identifiable {
    let id: UUID
}
