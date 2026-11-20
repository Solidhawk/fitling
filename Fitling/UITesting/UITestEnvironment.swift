#if DEBUG
import Foundation
import SwiftUI
import FitlingCore

/// Launch arguments for the UI test: the simulator in CI cannot sign in for real, so the app runs
/// on `FakeAuthProvider`, `FakeRemoteStore` and an in-memory store. Never compiled into a release build.
@MainActor
enum UITestEnvironment {
    /// `--ui-testing-on-disk` keeps the database in a real file, as on a device.
    /// `--ui-testing-with-profile` starts signed in with a finished onboarding and a partner, on the home screen.
    /// `--ui-testing-partner-gallery` shows every species in every look, for approving the drawings.
    /// `--ui-testing-dark` forces dark mode; setting the appearance from XCUITest did not reach the app on the CI simulator.
    static var colorScheme: ColorScheme? {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-dark") ? .dark : nil
    }

    static func makeIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) throws -> AppEnvironment? {
        let state: AuthState
        if arguments.contains("--ui-testing-signed-out") {
            state = .signedOut
        } else if arguments.contains("--ui-testing") || arguments.contains("--ui-testing-with-profile") {
            state = .signedIn(userID: UUID(), usesApple: false)
        } else {
            return nil
        }
        let container = try makeModelContainer(inMemory: !arguments.contains("--ui-testing-on-disk"))
        let sync = SyncEngine(container: container, remote: FakeRemoteStore(), tables: SyncTables.all)
        if arguments.contains("--ui-testing-with-profile"), case let .signedIn(userID, _) = state {
            insertSampleProfile(userID: userID, into: sync)
        }
        let source = FakeProductSource()
        source.products[sampleProduct.gtin ?? ""] = sampleProduct
        let food = FoodServices(source: source, search: FakeProductSearch())
        let offerSource = FakeOfferSource()
        offerSource.offerRecords = FakeOfferSource.sample(today: Day(.now, timeZone: .current))
        let root = RootViewModel(auth: FakeAuthProvider(state: state), sync: sync, food: food, reminders: FakeReminderDelivery(), health: FakeHealthReader(),
            shopping: ShoppingServices(sharing: FakeListSharing(), offers: offerSource)
        )
        return AppEnvironment(container: container, root: root)
    }

    /// The product the UI test scans: a real Open Food Facts answer (the lookup-product fixture).
    static let sampleProduct = ProductRecord(
        id: UUID(), ownerID: nil, source: "off", sourceID: "8712100849084", gtin: "8712100849084",
        name: LocalizedText(["de": "Double Caramel"]), brand: "Magnum, Unilever", searchName: "double caramel magnum, unilever",
        quantityUnit: "ml", servingSize: 88, servingLabel: nil, kcal100: 338, protein100: 3.2, carbs100: 36, sugars100: 33,
        fat100: 20, saturatedFat100: 14, fiber100: nil, salt100: 0.17, imageURL: nil, isVerified: true,
        fetchedAt: .now, updatedAt: .now, deletedAt: nil, syncedAt: .now
    )

    private static func insertSampleProfile(userID: UUID, into sync: SyncEngine) {
        let body = BodyProfile(birthDay: Day(year: 1996, month: 1, day: 10)!, sex: .male, heightCm: 180, weightKg: 80, activityLevel: .moderate, goal: .maintain)
        let targets = NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77)
        sync.context.insert(UserProfile(id: userID, healthConsentAt: .now, healthConsentVersion: 1, body: body, targets: targets, targetsAreManual: false, updatedAt: .now))
        sync.context.recordTargets(targets, for: userID, from: Day(.now, timeZone: .current), at: .now)
        let partner = CreatureState(species: .owl, colorIndex: 0, tone: .sweet, createdOn: Day(.now, timeZone: .current))
        sync.context.insert(Creature(userID: userID, name: "Pip", state: partner, updatedAt: .now))
        try? sync.context.save()
    }
}
#endif
