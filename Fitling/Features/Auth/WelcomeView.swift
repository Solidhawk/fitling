import AuthenticationServices
import SwiftUI
import FitlingCore

struct WelcomeView: View {
    let auth: any AuthProviding
    @State private var viewModel: WelcomeViewModel
    @State private var nonce = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The system Apple button sizes its label from its height, so it grows with the text too.
    @ScaledMetric(relativeTo: .headline) private var appleButtonHeight = ButtonMetrics.height

    init(auth: any AuthProviding) {
        self.auth = auth
        _viewModel = State(initialValue: WelcomeViewModel(auth: auth))
    }

    var body: some View {
        NavigationStack {
            // The catalog fills the screen; the sign-in actions sit at the bottom, within thumb reach.
            // At accessibility sizes the actions would cover most of the screen, so there they
            // scroll along below the catalog.
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("welcome.title")
                            .font(.largeTitle.weight(.heavy))
                            .accessibilityAddTraits(.isHeader)
                        Text("welcome.tagline")
                            .font(.title3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Color.ink)
                    catalog
                    if dynamicTypeSize.isAccessibilitySize {
                        actions
                    }
                }
                .padding(Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.ground)
            .safeAreaInset(edge: .bottom) {
                if !dynamicTypeSize.isAccessibilitySize {
                    actions
                        .padding(Spacing.l)
                        .background(Color.ground)
                }
            }
        }
    }

    /// The four species as a catalog: who can grow along with you.
    @ViewBuilder
    private var catalog: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Spacing.m) {
                ForEach(Species.allCases, id: \.self) { species in
                    FigureCard(species: species)
                }
            }
        } else {
            Grid(horizontalSpacing: Spacing.m, verticalSpacing: Spacing.m) {
                GridRow {
                    FigureCard(species: .sprout)
                    FigureCard(species: .ember)
                }
                GridRow {
                    FigureCard(species: .pip)
                    FigureCard(species: .pebble)
                }
            }
        }
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
            .frame(height: min(appleButtonHeight, ButtonMetrics.largestHeight))
            // The HIG allows a pill shape, which matches the other buttons.
            .clipShape(Capsule())
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
