import AuthenticationServices
import SwiftData
import SwiftUI

struct AccountView: View {
    let viewModel: AccountViewModel
    @State private var showsUnsyncedWarning = false
    @State private var exported: ExportedFiles?
    @State private var exportFailed = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section {
                Button("account.export", action: export)
            } footer: {
                Text(exportFailed ? LocalizedStringKey("account.export.failed") : LocalizedStringKey("account.export.footer"))
                    .foregroundStyle(Color.ink)
            }
            .listRowBackground(Color.card)
            Section {
                NavigationLink("account.about") { AboutView() }
            }
            .listRowBackground(Color.card)
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
        .sheet(item: $exported) { files in
            ShareSheet(items: files.urls)
        }
    }

    /// Writes the export to a new folder in the temporary directory and offers it to share or save.
    private func export() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Fitling-\(UUID().uuidString)")
        do {
            exported = ExportedFiles(urls: try DataExport.write(DataExport.tables(in: modelContext), to: folder, exportedAt: .now))
            exportFailed = false
        } catch {
            exportFailed = true
        }
    }
}

private struct ExportedFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// The system share sheet: save to Files, AirDrop, mail.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
