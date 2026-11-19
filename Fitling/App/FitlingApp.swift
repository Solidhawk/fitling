import SwiftData
import SwiftUI

/// The foundation opens the local database and shows nothing yet: the screens are built in
/// docs/TASKS.md, starting with the root view in phase 1.
@main
struct FitlingApp: App {
    private let container = Result { try makeModelContainer(inMemory: false) }

    var body: some Scene {
        WindowGroup {
            switch container {
            case let .success(container):
                Color.clear
                    .modelContainer(container)
            case .failure:
                ContentUnavailableView {
                    Label("error.configuration.title", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("error.configuration.body")
                }
            }
        }
    }
}
