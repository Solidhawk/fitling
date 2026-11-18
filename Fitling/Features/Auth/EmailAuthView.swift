import SwiftUI

struct EmailAuthView: View {
    let auth: any AuthProviding
    @State private var viewModel: EmailAuthViewModel

    init(auth: any AuthProviding, mode: EmailAuthViewModel.Mode) {
        self.auth = auth
        _viewModel = State(initialValue: EmailAuthViewModel(auth: auth, mode: mode))
    }

    private var isSignUp: Bool { viewModel.mode == .signUp }
    private var titleKey: LocalizedStringKey { isSignUp ? "auth.signUp.title" : "auth.signIn.title" }
    private var submitKey: LocalizedStringKey { isSignUp ? "auth.signUp.submit" : "auth.signIn.submit" }
    private var switchKey: LocalizedStringKey { isSignUp ? "auth.switch.toSignIn" : "auth.switch.toSignUp" }

    var body: some View {
        Form {
            Section {
                TextField("auth.email.field", text: $viewModel.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("auth.password.field", text: $viewModel.password)
                    .textContentType(isSignUp ? .newPassword : .password)
            } footer: {
                if isSignUp { Text("auth.password.hint") }
            }
            .listRowBackground(Color.card)

            Section {
                SubmitButton(title: submitKey, isWorking: viewModel.isWorking) {
                    Task { await viewModel.submit() }
                }
                .disabled(!viewModel.canSubmit)
                .accessibilityIdentifier("auth.submit")
                .buttonRow()
            } footer: {
                if let key = viewModel.messageKey {
                    Text(LocalizedStringKey(key)).foregroundStyle(Color.ink)
                }
            }

            Section {
                Button(switchKey) {
                    viewModel.mode = isSignUp ? .signIn : .signUp
                }
                if !isSignUp {
                    NavigationLink("auth.forgot.link") {
                        ForgotPasswordView(auth: auth, email: viewModel.email)
                    }
                }
            }
            .listRowBackground(Color.card)
        }
        .groundBackground()
        .navigationTitle(titleKey)
    }
}
