import SwiftUI

struct ForgotPasswordView: View {
    let auth: any AuthProviding
    @State private var viewModel: ForgotPasswordViewModel

    init(auth: any AuthProviding, email: String) {
        self.auth = auth
        let viewModel = ForgotPasswordViewModel(auth: auth)
        viewModel.email = email
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                TextField("auth.email.field", text: $viewModel.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .listRowBackground(Color.card)
            Section {
                SubmitButton(title: "auth.forgot.submit", isWorking: viewModel.isWorking) {
                    Task { await viewModel.submit() }
                }
                .disabled(!viewModel.canSubmit)
                .buttonRow()
            } footer: {
                if let key = viewModel.messageKey {
                    Text(LocalizedStringKey(key)).foregroundStyle(Color.ink)
                }
            }
            Section {
                NavigationLink("auth.forgot.createAccount") {
                    EmailAuthView(auth: auth, mode: .signUp)
                }
            }
            .listRowBackground(Color.card)
        }
        .groundBackground()
        .navigationTitle("auth.forgot.title")
    }
}

/// Shown as a sheet after a password-reset link opened the app.
struct ResetPasswordView: View {
    @State private var viewModel: ResetPasswordViewModel
    @Environment(\.dismiss) private var dismiss

    init(auth: any AuthProviding) {
        _viewModel = State(initialValue: ResetPasswordViewModel(auth: auth))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("auth.reset.field", text: $viewModel.password)
                        .textContentType(.newPassword)
                } footer: {
                    Text("auth.password.hint")
                }
                .listRowBackground(Color.card)
                Section {
                    SubmitButton(title: "auth.reset.submit", isWorking: viewModel.isWorking) {
                        Task { await viewModel.submit() }
                    }
                    .disabled(!viewModel.canSubmit)
                    .buttonRow()
                } footer: {
                    if let key = viewModel.messageKey {
                        Text(LocalizedStringKey(key)).foregroundStyle(Color.ink)
                    }
                }
            }
            .groundBackground()
            .navigationTitle("auth.reset.title")
            .onChange(of: viewModel.isDone) { _, isDone in
                if isDone { dismiss() }
            }
        }
    }
}

struct VerifyEmailView: View {
    @State private var viewModel: VerifyEmailViewModel

    init(auth: any AuthProviding, email: String) {
        _viewModel = State(initialValue: VerifyEmailViewModel(auth: auth, email: email))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                // The envelope as a sticker badge, in the same keyline style as the figures.
                Image(systemName: "envelope.fill")
                    .font(.title)
                    .foregroundStyle(Color.onRibbon)
                    .frame(width: 72, height: 72)
                    .background(Color.pip, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                    .accessibilityHidden(true)
                Text("auth.verify.title")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(Color.ink)
                Text("auth.verify.body \(viewModel.email)")
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await viewModel.resend() }
                } label: {
                    Text("auth.verify.resend")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(viewModel.isWorking)

                Button("auth.verify.otherAddress") {
                    viewModel.useOtherAddress()
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)

                if let key = viewModel.messageKey {
                    Text(LocalizedStringKey(key)).font(.footnote).foregroundStyle(Color.ink)
                }
            }
            .padding(Spacing.l)
        }
        .background(Color.ground)
    }
}
