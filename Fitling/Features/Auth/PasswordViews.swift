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
            Section {
                Button {
                    Task { await viewModel.submit() }
                } label: {
                    HStack {
                        Text("auth.forgot.submit")
                        if viewModel.isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!viewModel.canSubmit)

                if let key = viewModel.messageKey {
                    Text(LocalizedStringKey(key)).foregroundStyle(.secondary)
                }
            }
            Section {
                NavigationLink("auth.forgot.createAccount") {
                    EmailAuthView(auth: auth, mode: .signUp)
                }
            }
        }
        .paperGround()
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
                Section {
                    Button {
                        Task { await viewModel.submit() }
                    } label: {
                        HStack {
                            Text("auth.reset.submit")
                            if viewModel.isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!viewModel.canSubmit)

                    if let key = viewModel.messageKey {
                        Text(LocalizedStringKey(key)).foregroundStyle(.secondary)
                    }
                }
            }
            .paperGround()
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
                Image(systemName: "envelope")
                    .font(.largeTitle)
                    .foregroundStyle(Color.ink)
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
        .background(Color.paper)
    }
}
