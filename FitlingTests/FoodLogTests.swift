import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

@MainActor
struct FoodFixture {
    let container: ModelContainer
    let userID = UUID()
    /// 2026-11-18, 11:06 UTC.
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    let source = FakeProductSource()
    let search = FakeProductSearch()
    var context: ModelContext { container.mainContext }
    var today: Day { Day(now, timeZone: .gmt) }

    init() throws {
        container = try makeModelContainer(inMemory: true)
    }

    var diary: FoodDiary {
        FoodDiary(context: context, userID: userID, now: { [now] in now })
    }

    func lookup() -> ProductLookup {
        ProductLookup(context: context, source: source, now: { [now] in now })
    }

    func logViewModel(meal: MealSlot = .lunch) -> LogFoodViewModel {
        LogFoodViewModel(meal: meal, day: today, diary: diary, lookup: lookup(), search: search)
    }

    func portion(_ product: Product, meal: MealSlot = .lunch) -> PortionViewModel {
        PortionViewModel(product: product, diary: diary, meal: meal, day: today, languages: ["nl"])
    }

    @discardableResult
    func product(_ name: String, kcal: Double? = 250, protein: Double? = 10, carbs: Double? = 40, fat: Double? = 5, serving: Double? = nil, gtin: String? = nil) -> Product {
        let product = Product(id: UUID(), ownerID: nil, source: "off", name: LocalizedText(["nl": name]), quantityUnit: "g", updatedAt: now)
        product.kcal100 = kcal
        product.protein100 = protein
        product.carbs100 = carbs
        product.fat100 = fat
        product.servingSize = serving
        product.gtin = gtin
        product.searchName = FoodDiary.searchKey(name)
        product.fetchedAt = now
        product.needsPush = false
        context.insert(product)
        try? context.save()
        return product
    }

    func profile(kcal: Int = 2760, countsWorkouts: Bool = false) -> UserProfile {
        let body = BodyProfile(birthDay: Day(year: 1996, month: 1, day: 10)!, sex: .male, heightCm: 180, weightKg: 80, activityLevel: .moderate, goal: .maintain)
        let profile = UserProfile(
            id: userID, healthConsentAt: now, healthConsentVersion: 1, body: body,
            targets: NutritionTargets(kcal: kcal, proteinG: 128, carbsG: 389, fatG: 77), targetsAreManual: false, updatedAt: now
        )
        profile.countsWorkoutEnergy = countsWorkouts
        context.insert(profile)
        try? context.save()
        return profile
    }

    func dayViewModel(_ profile: UserProfile) -> DayViewModel {
        DayViewModel(profile: profile, context: context, timeZone: .gmt, now: { [now] in now })
    }
}

// MARK: - 2.5 Scannen

@MainActor
@Suite struct ScanTests {
    let fixture: FoodFixture
    init() throws { fixture = try FoodFixture() }

    @Test func scanOfAKnownProductOpensTheLogSheet() async {
        let product = fixture.product("Pindakaas", gtin: "8712100849084")
        let viewModel = fixture.logViewModel()
        await viewModel.handleScan("8712100849084")
        #expect(viewModel.scanOutcome == .product(product.id))
    }

    @Test func scanOfAnUnknownProductOffersToAddIt() async {
        let viewModel = fixture.logViewModel()
        await viewModel.handleScan("4006381333931")
        #expect(viewModel.scanOutcome == .unknown(gtin: "4006381333931"))
    }

    @Test func misreadIsIgnored() async {
        let viewModel = fixture.logViewModel()
        await viewModel.handleScan("4006381333932")
        #expect(viewModel.scanOutcome == nil)
        #expect(fixture.source.calls.isEmpty)
    }

    @Test func scanWhileOfflineKeepsTheBarcode() async {
        fixture.source.isOffline = true
        let viewModel = fixture.logViewModel()
        await viewModel.handleScan("4006381333931")
        #expect(viewModel.scanOutcome == .unavailable(gtin: "4006381333931"))
    }
}

// MARK: - 2.6 Loggen

@MainActor
@Suite struct LoggingTests {
    let fixture: FoodFixture
    init() throws { fixture = try FoodFixture() }

    @Test func loggingStoresASnapshotOfNameAndValues() throws {
        let product = fixture.product("Volkorenbrood", kcal: 250, protein: 10, carbs: 40, fat: 5)
        let portion = fixture.portion(product, meal: .breakfast)
        portion.unit = .gram
        portion.quantity = 150
        let entry = try #require(portion.save())
        #expect(entry.name == "Volkorenbrood")
        #expect(entry.kcal == 375)
        #expect(entry.proteinG == 15)
        #expect(entry.carbsG == 60)
        #expect(entry.fatG == 7.5)
        #expect(entry.quantity == 150)
        #expect(entry.quantityUnit == "g")
        #expect(entry.meal == "breakfast")
        #expect(entry.consumedOn == fixture.today.isoString)
        #expect(entry.productID == product.id)
        #expect(entry.needsPush)
    }

    @Test func editingAProductLaterDoesNotChangeOldEntries() throws {
        let product = fixture.product("Yoghurt", kcal: 60)
        let portion = fixture.portion(product)
        portion.unit = .gram
        portion.quantity = 200
        let entry = try #require(portion.save())
        product.kcal100 = 90
        product.name = LocalizedText(["nl": "Griekse yoghurt"])
        #expect(entry.kcal == 120)
        #expect(entry.name == "Yoghurt")
    }

    @Test func servingsUseTheServingSize() throws {
        let product = fixture.product("Appeltaart", kcal: 280, serving: 120)
        let portion = fixture.portion(product)
        #expect(portion.unit == .serving)
        #expect(portion.units == [.serving, .gram])
        portion.quantity = 1.5
        let entry = try #require(portion.save())
        #expect(entry.kcal == 504)
        #expect(entry.quantityUnit == "serving")
    }

    @Test func productWithoutKcalAsksForIt() throws {
        let shared = fixture.product("Onbekende reep", kcal: nil, protein: 5, carbs: nil, fat: 12)
        let portion = fixture.portion(shared)
        portion.unit = .gram
        portion.quantity = 50
        #expect(portion.needsKcal)
        #expect(!portion.canSave)
        portion.kcalOnPackage = 480

        let entry = try #require(portion.save())

        #expect(entry.kcal == 240)
        #expect(entry.productID != shared.id)
        let copyID = try #require(entry.productID)
        let copy = try #require(fixture.diary.product(copyID))
        #expect(copy.ownerID == fixture.userID)
        #expect(copy.source == "user")
        #expect(copy.kcal100 == 480)
        #expect(copy.needsPush)
        #expect(shared.kcal100 == nil)
    }

    @Test func unknownMacrosAreStoredAsUnknown() throws {
        let product = fixture.product("Chips", kcal: 530, protein: nil, carbs: 50, fat: 33)
        let portion = fixture.portion(product)
        #expect(portion.hasUnknownMacros)
        portion.unit = .gram
        portion.quantity = 30
        let entry = try #require(portion.save())
        #expect(entry.proteinG == nil)
    }

    @Test func recentShowsEachProductOnce() throws {
        let bread = fixture.product("Brood")
        let cheese = fixture.product("Kaas")
        for product in [bread, cheese, bread] {
            let portion = fixture.portion(product)
            portion.unit = .gram
            portion.quantity = 50
            try #require(portion.save())
        }
        #expect(Set(fixture.diary.recentProducts().map(\.id)) == [bread.id, cheese.id])
        #expect(fixture.diary.recentProducts().count == 2)
    }

    @Test func favoritesCanBeSetAndCleared() {
        let product = fixture.product("Havermout")
        let portion = fixture.portion(product)
        portion.toggleFavorite()
        #expect(fixture.diary.favoriteProducts().map(\.id) == [product.id])
        portion.toggleFavorite()
        #expect(fixture.diary.favoriteProducts().isEmpty)
    }

    @Test func searchFindsLocalProductsFirstAndAddsOnlineOnes() async {
        let local = fixture.product("Pindakaas naturel")
        var online = local.record
        online.id = UUID()
        online.name = LocalizedText(["nl": "Pindakaas crunchy"])
        online.searchName = "pindakaas crunchy"
        fixture.search.records = [online, local.record]
        let viewModel = fixture.logViewModel()
        viewModel.query = "Pindakáas"

        await viewModel.runSearch()

        #expect(viewModel.localResults.map(\.id) == [local.id])
        #expect(viewModel.onlineResults.map(\.id) == [online.id])
        #expect(fixture.search.terms == ["pindakaas"])
        #expect(fixture.diary.product(online.id) != nil)
    }

    @Test func aShortQueryStaysOnTheDevice() async {
        let viewModel = fixture.logViewModel()
        viewModel.query = "pi"
        await viewModel.runSearch()
        #expect(fixture.search.terms.isEmpty)
    }
}

// MARK: - 2.8 Zelf een product toevoegen

@MainActor
@Suite struct AddProductTests {
    let fixture: FoodFixture
    init() throws { fixture = try FoodFixture() }

    func filledIn(gtin: String? = "8712100849084") -> AddProductViewModel {
        let viewModel = AddProductViewModel(diary: fixture.diary, gtin: gtin)
        viewModel.name = " Oma's appeltaart "
        viewModel.brand = "Bakkerij Jansen"
        viewModel.kcal = 280.44
        viewModel.protein = 3.2
        viewModel.carbs = 38
        viewModel.servingSize = 120
        return viewModel
    }

    @Test func savesAPrivateProductThatSyncs() throws {
        let product = try #require(filledIn().save())
        #expect(product.ownerID == fixture.userID)
        #expect(product.source == "user")
        #expect(product.gtin == "8712100849084")
        #expect(product.kcal100 == 280.4)
        #expect(product.fat100 == nil)
        #expect(product.servingSize == 120)
        #expect(product.searchName == "oma's appeltaart bakkerij jansen")
        #expect(product.needsPush)
        #expect(product.name.values.values.first == "Oma's appeltaart")
    }

    @Test func aBarcodeIsOptionalButMustBeValid() {
        let viewModel = filledIn(gtin: nil)
        #expect(viewModel.canSave)
        viewModel.gtin = "8712100849085"
        #expect(!viewModel.canSave)
        viewModel.gtin = "036000291452"
        #expect(viewModel.save()?.gtin == "0036000291452")
    }

    @Test func valuesOutsideTheDatabaseLimitsBlock() {
        let viewModel = filledIn()
        viewModel.kcal = 950
        #expect(!viewModel.canSave)
        viewModel.kcal = 300
        viewModel.protein = 120
        #expect(!viewModel.canSave)
        viewModel.protein = 3
        viewModel.name = "  "
        #expect(!viewModel.canSave)
    }
}

// MARK: - 2.7 Dagoverzicht

@MainActor
@Suite struct DayOverviewTests {
    let fixture: FoodFixture
    init() throws { fixture = try FoodFixture() }

    @Test func usesTheTargetsThatAppliedOnThatDay() {
        let profile = fixture.profile(kcal: 2500)
        let targets = { (kcal: Int) in NutritionTargets(kcal: kcal, proteinG: 128, carbsG: 300, fatG: 70) }
        fixture.context.insert(TargetPeriod(id: UUID(), userID: fixture.userID, effectiveOn: fixture.today.adding(-10), targets: targets(2000), updatedAt: fixture.now))
        fixture.context.insert(TargetPeriod(id: UUID(), userID: fixture.userID, effectiveOn: fixture.today.adding(-2), targets: targets(2500), updatedAt: fixture.now))
        let viewModel = fixture.dayViewModel(profile)

        #expect(viewModel.targets.kcal == 2500)
        viewModel.show(fixture.today.adding(-5))
        #expect(viewModel.targets.kcal == 2000)
        viewModel.show(fixture.today.adding(-20))
        #expect(viewModel.targets.kcal == 2500)
    }

    @Test func reportsUnknownMacros() throws {
        let profile = fixture.profile()
        for (name, protein) in [("Chips", nil), ("Kwark", 10.0)] as [(String, Double?)] {
            let portion = fixture.portion(fixture.product(name, protein: protein))
            portion.unit = .gram
            portion.quantity = 100
            try #require(portion.save())
        }
        let viewModel = fixture.dayViewModel(profile)
        #expect(viewModel.totals.entryCount == 2)
        #expect(viewModel.totals.unknownProtein == 1)
        #expect(viewModel.totals.proteinG == 10)
        #expect(viewModel.totals.kcal == 500)
    }

    @Test func waterAddsUp() {
        let viewModel = fixture.dayViewModel(fixture.profile())
        viewModel.addGlass()
        viewModel.addGlass()
        #expect(viewModel.waterMl == 500)
    }

    @Test func mealsAreKeptApartAndDeletedEntriesDisappear() throws {
        let profile = fixture.profile()
        let breakfast = fixture.portion(fixture.product("Brood"), meal: .breakfast)
        breakfast.unit = .gram
        breakfast.quantity = 100
        let entry = try #require(breakfast.save())
        let dinner = fixture.portion(fixture.product("Pasta"), meal: .dinner)
        dinner.unit = .gram
        dinner.quantity = 200
        try #require(dinner.save())
        let viewModel = fixture.dayViewModel(profile)
        #expect(viewModel.kcal(of: .breakfast) == 250)
        #expect(viewModel.kcal(of: .dinner) == 500)

        viewModel.delete(entry)

        #expect(viewModel.kcal(of: .breakfast) == 0)
        #expect(entry.deletedAt != nil)
        #expect(entry.needsPush)
    }

    @Test func workoutEnergyRaisesTheTargetWhenChosen() {
        let profile = fixture.profile(kcal: 2500, countsWorkouts: true)
        fixture.context.insert(DayActivity(day: fixture.today, workoutKcal: 400, updatedAt: fixture.now))
        #expect(fixture.dayViewModel(profile).targets.kcal == 2700)
        profile.countsWorkoutEnergy = false
        #expect(fixture.dayViewModel(profile).targets.kcal == 2500)
    }

    @Test func theFutureCannotBeShown() {
        let viewModel = fixture.dayViewModel(fixture.profile())
        viewModel.show(fixture.today.adding(3))
        #expect(viewModel.day == fixture.today)
        #expect(viewModel.isToday)
    }
}

// MARK: - 2.10 Afbeeldingen

@Suite struct ProductThumbnailTests {
    @Test func thePlaceholderShowsTheFirstLetterOrDigit() {
        #expect(ProductThumbnail.initial(of: "volkorenbrood") == "V")
        #expect(ProductThumbnail.initial(of: "  'Oma's taart") == "O")
        #expect(ProductThumbnail.initial(of: "7up") == "7")
        #expect(ProductThumbnail.initial(of: "") == "–")
    }
}
