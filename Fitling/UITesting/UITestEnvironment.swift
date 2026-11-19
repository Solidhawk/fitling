#if DEBUG
import Foundation
import SwiftUI

/// Launch arguments for the UI test: the simulator in CI cannot sign in for real, so the app runs
/// on `FakeAuthProvider`, `FakeRemoteStore` and an in-memory store. Never compiled into a release build.
@MainActor
enum UITestEnvironment {
    /// `--ui-testing-dark` forces dark mode; setting the appearance from XCUITest did not reach the app on the CI simulator.
    static var colorScheme: ColorScheme? {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-dark") ? .dark : nil
    }

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
        let sync = SyncEngine(container: container, remote: FakeRemoteStore(), tables: SyncTables.all)
        return AppEnvironment(container: container, root: RootViewModel(auth: FakeAuthProvider(state: state), sync: sync))
    }
}
#endif
