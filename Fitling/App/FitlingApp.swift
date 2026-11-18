import SwiftData
import SwiftUI

@main
struct FitlingApp: App {
    @State private var environment = AppEnvironment.make()

    var body: some Scene {
        WindowGroup {
            switch environment {
            case let .success(environment):
                RootView(viewModel: environment.root, context: environment.container.mainContext)
                    .modelContainer(environment.container)
                    #if DEBUG
                    .preferredColorScheme(UITestEnvironment.colorScheme)
                    #endif
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

@MainActor
struct AppEnvironment {
    let container: ModelContainer
    let root: RootViewModel

    static func make() -> Result<AppEnvironment, any Error> {
        do {
            #if DEBUG
            if let testing = try UITestEnvironment.makeIfRequested() { return .success(testing) }
            #endif
            let config = try AppConfiguration.fromBundle()
            let client = makeSupabaseClient(config)
            let container = try makeModelContainer(inMemory: false)
            let sync = ProfileSync.live(client: client, context: container.mainContext)
            return .success(AppEnvironment(container: container, root: RootViewModel(auth: AuthService(client: client), sync: sync)))
        } catch {
            return .failure(error)
        }
    }
}
