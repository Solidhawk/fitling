import SwiftData
import SwiftUI

@main
struct FitlingApp: App {
    @State private var environment = AppEnvironment.make()

    init() {
        NavigationBarStyle.apply()
        ImageCache.configure()
    }

    var body: some Scene {
        WindowGroup {
            switch environment {
            case let .success(environment):
                RootView(viewModel: environment.root)
                    .modelContainer(environment.container)
                    .fontDesign(.rounded)
                    // Checkmarks, links, the caret and toolbar buttons in ink instead of system blue.
                    .tint(Color.ink)
                    #if DEBUG
                    .preferredColorScheme(UITestEnvironment.colorScheme)
                    #endif
            case .failure:
                ContentUnavailableView {
                    Label("error.configuration.title", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("error.configuration.body")
                }
                .fontDesign(.rounded)
                .tint(Color.ink)
                .accessibilityIdentifier("error.configuration")
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
            let sync = SyncEngine(container: container, remote: SupabaseRemoteStore(client: client), tables: SyncTables.all)
            let food = FoodServices(source: SupabaseProductSource(client: client), search: SupabaseProductSearch(client: client))
            return .success(AppEnvironment(container: container, root: RootViewModel(auth: AuthService(client: client), sync: sync, food: food)))
        } catch {
            return .failure(error)
        }
    }
}
