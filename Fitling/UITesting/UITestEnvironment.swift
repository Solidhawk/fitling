#if DEBUG
import Foundation

/// Launch arguments for the UI test: the simulator in CI cannot sign in for real, so the app runs
/// on `FakeAuthProvider` and an in-memory store. Never compiled into a release build.
@MainActor
enum UITestEnvironment {
    static func makeIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) throws -> AppEnvironment? {
        let state: AuthState
        if arguments.contains("--ui-testing-signed-out") {
            state = .signedOut
        } else if arguments.contains("--ui-testing") {
            state = .signedIn(userID: UUID(), usesApple: false)
        } else {
            return nil
        }
        let container = try makeModelContainer(inMemory: true)
        let sync = ProfileSync(context: container.mainContext, fetchRemote: { _ in nil }, upsertRemote: { _ in })
        return AppEnvironment(container: container, root: RootViewModel(auth: FakeAuthProvider(state: state), sync: sync))
    }
}
#endif
