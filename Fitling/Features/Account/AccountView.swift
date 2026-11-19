import AuthenticationServices
import SwiftUI

struct AccountView: View {
    let viewModel: AccountViewModel
    @State private var showsUnsyncedWarning = false

    var body: some View {
        List {
            Section {
                Button("account.signOut") {
                    Task {
                        if await viewModel.signOut(force: false) == .unsyncedChanges {
                            showsUnsyncedWarning = true
                        }
                    }
                }
                .disabled(viewModel.isWorking)
            } footer: {
                if let key = viewModel.messageKey { Text(LocalizedStringKey(key)).foregroundStyle(Color.ink) }
            }
            .listRowBackground(Color.card)
            Section {
                NavigationLink("account.delete") {
                    DeleteAccountView(viewModel: viewModel)
                }
            }
            .listRowBackground(Color.card)
        }
        .groundBackground()
        .navigationTitle("account.title")
        .alert("account.unsynced.title", isPresented: $showsUnsyncedWarning) {
            Button("account.unsynced.force", role: .destructive) {
                Task { _ = await viewModel.signOut(force: true) }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("account.unsynced.body")
        }
    }
}

/// Deleting is final, so it asks once more: Apple accounts confirm with Apple (which also supplies
/// the code the server needs to revoke the Apple token), others confirm in a dialog.
struct DeleteAccountView: View {
    let viewModel: AccountViewModel
    @State private var confirming = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                Text("account.delete.body")
                if viewModel.usesApple {
                    Text("account.delete.apple").font(.footnote)
                }
            }
            .listRowBackground(Color.card)
            Section {
                if viewModel.usesApple {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = []
                    } onCompletion: { result in
                        guard case let .success(authorization) = result,
                              let credential = AppleSignIn.credential(from: authorization) else { return }
                        let code = credential.authorizationCode
                        Task { await viewModel.deleteAccount(appleAuthorizationCode: code) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: ButtonMetrics.height)
                    .clipShape(Capsule())
                    .buttonRow()
                } else {
                    Button("account.delete.confirm", role: .destructive) { confirming = true }
                        .disabled(viewModel.isWorking)
                        .listRowBackground(Color.card)
                }
            } footer: {
                if let key = viewModel.messageKey { Text(LocalizedStringKey(key)).foregroundStyle(Color.ink) }
            }
        }
        .groundBackground()
        .navigationTitle("account.delete")
        .confirmationDialog("account.delete", isPresented: $confirming, titleVisibility: .visible) {
            Button("account.delete.confirm", role: .destructive) {
                Task { await viewModel.deleteAccount(appleAuthorizationCode: nil) }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("account.delete.body")
        }
    }
}
