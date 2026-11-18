import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    let auth: any AuthProviding
    @State private var viewModel: WelcomeViewModel
    @State private var nonce = ""
    @Environment(\.colorScheme) private var colorScheme

    init(auth: any AuthProviding) {
        self.auth = auth
        _viewModel = State(initialValue: WelcomeViewModel(auth: auth))
    }

    var body: some View {
        NavigationStack {
            // The composition fills the screen; the sign-in actions sit at the bottom, within thumb reach.
            ScrollView {
                composition
                    .containerRelativeFrame(.vertical) { length, _ in max(300, length - Spacing.l * 2) }
                    .padding(Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.paper)
            .safeAreaInset(edge: .bottom) {
                actions
                    .padding(Spacing.l)
                    .background(Color.paper)
            }
        }
    }

    /// The colour system introduced as a De Stijl panel: the three fields are the macro colours
    /// used everywhere else in the app.
    private var composition: some View {
        HStack(spacing: Rule.width) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("welcome.title")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(Color.ink)
                Spacer(minLength: Spacing.xl)
                Text("welcome.tagline")
                    .font(.title3)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.paper)

            VStack(spacing: Rule.width) {
                legendField("welcome.legend.protein", fill: .protein, text: .white)
                legendField("welcome.legend.carbs", fill: .carbs, text: .onCarbs)
                legendField("welcome.legend.fat", fill: .fat, text: .white)
            }
            .frame(width: 128)
            .accessibilityHidden(true)
        }
        .frame(minHeight: 300)
        .padding(Rule.width)
        .background(Color.ink)
    }

    private func legendField(_ key: LocalizedStringKey, fill: Color, text: Color) -> some View {
        Text(key)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(text)
            .padding(Spacing.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background(fill)
    }

    private var actions: some View {
        VStack(spacing: Spacing.m) {
            SignInWithAppleButton(.continue) { request in
                nonce = AppleSignIn.makeNonce()
                request.requestedScopes = [.email]
                request.nonce = AppleSignIn.sha256(nonce)
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = AppleSignIn.credential(from: authorization) else {
                        viewModel.appleFailed(ASAuthorizationError(.failed))
                        return
                    }
                    let nonce = nonce
                    Task { await viewModel.signInWithApple(credential, nonce: nonce) }
                case .failure(let error):
                    viewModel.appleFailed(error)
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .accessibilityIdentifier("welcome.apple")

            Button {
                Task { await viewModel.signInWithGoogle() }
            } label: {
                Text("welcome.google")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(viewModel.isWorking)
            .accessibilityIdentifier("welcome.google")

            NavigationLink {
                EmailAuthView(auth: auth, mode: .signIn)
            } label: {
                Text("welcome.email")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("welcome.email")

            if let key = viewModel.messageKey {
                Text(LocalizedStringKey(key))
                    .font(.footnote)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
