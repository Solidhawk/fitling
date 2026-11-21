import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

@MainActor
struct ShoppingFixture {
    let menu: MenuFixture
    let remote = FakeRemoteStore()
    let sharing = FakeListSharing()
    let offers = FakeOfferSource()
    let sync: SyncEngine

    init() throws {
        menu = try MenuFixture()
        sync = SyncEngine(container: menu.container, remote: remote, tables: SyncTables.all, now: { [now = menu.now] in now })
    }

    var store: ShoppingStore {
        ShoppingStore(context: menu.context, userID: menu.userID, timeZone: .gmt, now: { [now = menu.now] in now }, language: "nl")
    }

    func viewModel(now: (() -> Date)? = nil) -> ShoppingViewModel {
        ShoppingViewModel(
            profile: menu.profile, sync: sync, services: ShoppingServices(sharing: sharing, offers: offers), defaults: menu.defaults,
            listName: "Boodschappen", ownerName: "Ik", timeZone: .gmt, now: now ?? { [now = menu.now] in now }
        )
    }

    var localOfferCount: Int {
        (try? menu.context.fetchCount(FetchDescriptor<Offer>())) ?? -1
    }
}

/// A clock a test can move forward.
final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// `count` offers of one shop, valid for a week from `today`.
func manyOffers(_ count: Int, in shop: String, today: Day) -> [OfferRecord] {
    (0..<count).map { number in
        OfferRecord(
            id: UUID(), supermarketID: shop, externalID: "x\(number)", title: "Product \(number)", searchTitle: "product \(number)",
            priceCents: 100, validFrom: today, validTo: today.adding(6)
        )
    }
}

// MARK: - 6.2 Lijst en items

@MainActor
@Suite struct ShoppingListTests {
    let fixture: ShoppingFixture
    init() throws { fixture = try ShoppingFixture() }

    @Test func theFirstListIsMadeOnTheDeviceWithTheUserAsOwner() {
        let list = fixture.store.ensureList(named: "Boodschappen", ownerName: "Ik")
        #expect(fixture.store.ensureList(named: "Andere", ownerName: "Ik").id == list.id)
        #expect(list.createdBy == fixture.menu.userID)
        let members = fixture.store.members(of: list)
        let roles = members.map(\.role)
        #expect(roles == ["owner"])
        #expect(members.allSatisfy { $0.needsPush })
    }

    @Test func itemsFollowTheShopAndCheckedOnesGoLast() {
        let list = fixture.store.ensureList(named: "Boodschappen", ownerName: "Ik")
        fixture.store.add("Melk", aisle: "dairy", to: list)
        let apples = fixture.store.add("Appels", aisle: "produce", to: list)
        fixture.store.add("Brood", aisle: "bakery", to: list)
        #expect(fixture.store.add("   ", to: list) == nil)
        fixture.store.toggle(apples!)
        let names = fixture.store.items(of: list).map(\.name)
        #expect(names == ["Brood", "Melk", "Appels"])
    }

    @Test func theMenuFillsTheListAndReplacesItsOwnItems() throws {
        fixture.menu.store.generate(seed: 1)
        let list = fixture.store.ensureList(named: "Boodschappen", ownerName: "Ik")
        fixture.store.add("Koffie", to: list)
        fixture.store.fill(list, from: fixture.menu.store.entries(), menu: fixture.menu.store)
        let first = fixture.store.items(of: list)
        #expect(first.contains { $0.source == "menu" })
        #expect(first.contains { $0.name == "Koffie" && $0.source == "manual" })

        let basket = try #require(first.first { $0.source == "menu" })
        fixture.store.toggle(basket)
        fixture.store.fill(list, from: fixture.menu.store.entries(), menu: fixture.menu.store)
        let second = fixture.store.items(of: list)
        #expect(second.filter { $0.source == "menu" && !$0.isChecked }.count == first.filter { $0.source == "menu" }.count)
        #expect(second.contains { $0.id == basket.id })
        #expect(second.contains { $0.name == "Koffie" })
    }

    @Test func loggedMealsAreNotBoughtAgain() throws {
        fixture.menu.store.generate(seed: 1)
        let entries = fixture.menu.store.entries()
        for entry in entries { fixture.menu.store.log(entry) }
        let list = fixture.store.ensureList(named: "Boodschappen", ownerName: "Ik")
        fixture.store.fill(list, from: entries, menu: fixture.menu.store)
        #expect(fixture.store.items(of: list).isEmpty)
    }

    @Test func shoppingRecordsKeepEveryColumn() throws {
        let list = fixture.store.ensureList(named: "Boodschappen", ownerName: "Ik")
        let item = try #require(fixture.store.add("Melk", quantity: 1000, unit: "ml", aisle: "dairy", to: list))
        #expect(try JSONDecoder().decode(ShoppingItemRecord.self, from: JSONEncoder().encode(item.record)) == item.record)
        #expect(try JSONDecoder().decode(ShoppingListRecord.self, from: JSONEncoder().encode(list.record)) == list.record)
    }
}

// MARK: - 6.3 Delen

@MainActor
@Suite struct SharingTests {
    let fixture: ShoppingFixture
    init() throws { fixture = try ShoppingFixture() }

    @Test func theOwnerIsAddedOnceTheListIsOnTheServer() async throws {
        let viewModel = fixture.viewModel()
        viewModel.reload()
        await viewModel.refresh()
        let list = try #require(viewModel.list)
        #expect(fixture.remote.row(list.id, in: "shopping_lists") != nil)
        let roles = try await fixture.sharing.members(of: list.id).map(\.role)
        #expect(roles == ["owner"])
        #expect(fixture.store.unsentMembers().isEmpty)
    }

    @Test func anInviteCanBeUsedToJoin() async throws {
        let viewModel = fixture.viewModel()
        viewModel.reload()
        await viewModel.createInvite()
        let code = try #require(viewModel.inviteCode)
        #expect(code.count == 12)

        #expect(await viewModel.join(code: "WRONGCODE123", name: "Sam") == false)
        #expect(viewModel.sharingProblem == .invalidInvite)
        #expect(await viewModel.join(code: code, name: "Sam"))
    }

    @Test func aFailingServerIsExplained() async {
        let viewModel = fixture.viewModel()
        viewModel.reload()
        fixture.sharing.failure = .network
        await viewModel.createInvite()
        #expect(viewModel.inviteCode == nil)
        #expect(viewModel.sharingProblem == .network)
    }
}

// MARK: - 6.7 Aanbiedingen

@MainActor
@Suite struct OfferTests {
    let fixture: ShoppingFixture
    init() throws { fixture = try ShoppingFixture() }

    @Test func theCheapestOfferOfTheFavouriteShopsIsShown() async throws {
        fixture.offers.offerRecords = FakeOfferSource.sample(today: fixture.menu.today)
        let viewModel = fixture.viewModel()
        viewModel.reload()
        viewModel.add("Tomatenblokjes")
        viewModel.add("Uien")
        viewModel.add("Wasmiddel")

        await viewModel.setFavorite("testmarkt", true)
        let tomatoes = try #require(viewModel.items.first { $0.name == "Tomatenblokjes" })
        #expect(viewModel.cheapest[tomatoes.id]?.priceCents == 79)

        await viewModel.setFavorite("proefsuper", true)
        #expect(viewModel.cheapest[tomatoes.id]?.priceCents == 69)
        let totals = Dictionary(uniqueKeysWithValues: viewModel.totals.map { ($0.supermarketID, $0) })
        #expect(totals["testmarkt"]?.itemsWithoutPrice == 1)
        #expect(totals["proefsuper"]?.itemsWithoutPrice == 2)
    }

    /// Two shops with the same possible offer for an item that is on the list twice: one question, with both
    /// shops, and one answer for all of it (UNFORGET S24).
    @Test func aPossibleOfferIsAskedOnceWithTheShopsThatHaveIt() async throws {
        fixture.offers.offerRecords = FakeOfferSource.sample(today: fixture.menu.today)
        let viewModel = fixture.viewModel()
        viewModel.reload()
        viewModel.add("Tomaat")
        viewModel.add("Tomaat")
        await viewModel.setFavorite("testmarkt", true)
        await viewModel.setFavorite("proefsuper", true)

        let question = try #require(viewModel.questions.first)
        #expect(viewModel.questions.count == 1)
        #expect(question.itemName == "Tomaat")
        #expect(question.offerTitle == "Tomatenblokjes 400 g")
        #expect(question.supermarketIDs == ["proefsuper", "testmarkt"])
        #expect(viewModel.totals.isEmpty)

        viewModel.confirm(question)
        #expect(viewModel.questions.isEmpty)
        let tomatoes = viewModel.items.filter { $0.name == "Tomaat" }
        #expect(tomatoes.count == 2)
        #expect(tomatoes.allSatisfy { viewModel.cheapest[$0.id]?.priceCents == 69 })
        #expect(viewModel.totals.map(\.supermarketID).sorted() == ["proefsuper", "testmarkt"])
    }

    @Test func offersOfOtherShopsAreIgnored() async {
        fixture.offers.offerRecords = FakeOfferSource.sample(today: fixture.menu.today)
        let viewModel = fixture.viewModel()
        viewModel.reload()
        viewModel.add("Tomatenblokjes")
        await viewModel.refreshOffers()
        viewModel.reload()
        #expect(viewModel.cheapest.isEmpty)
        #expect(viewModel.totals.isEmpty)
    }

    /// The Data API sends at most `max_rows` per request (1,000 by default); Albert Heijn alone has over 5,000
    /// offers (UNFORGET S23).
    @Test func everyOfferArrivesHoweverFewTheServerSendsPerRequest() async {
        fixture.offers.rowCap = 400
        fixture.offers.offerRecords = manyOffers(2_300, in: "testmarkt", today: fixture.menu.today)
        let viewModel = fixture.viewModel()
        viewModel.reload()
        await viewModel.setFavorite("testmarkt", true)
        #expect(fixture.localOfferCount == 2_300)
    }

    @Test func aRequestThatFailsHalfwayKeepsTheOffersThatWereThere() async {
        fixture.offers.offerRecords = FakeOfferSource.sample(today: fixture.menu.today)
        let viewModel = fixture.viewModel()
        viewModel.reload()
        await viewModel.setFavorite("testmarkt", true)
        await viewModel.setFavorite("proefsuper", true)
        #expect(fixture.localOfferCount == 3)

        fixture.offers.rowCap = 2
        fixture.offers.failFromOffset = 2
        await viewModel.refreshOffers(force: true)
        #expect(fixture.localOfferCount == 3)
    }

    /// The offers change once a night; opening the list again does not fetch them all again.
    @Test func offersAreFetchedAgainWhenOldWhenTheShopsChangeOrWhenAsked() async {
        fixture.offers.offerRecords = FakeOfferSource.sample(today: fixture.menu.today)
        let clock = TestClock(fixture.menu.now)
        let viewModel = fixture.viewModel(now: { clock.now })
        viewModel.reload()
        await viewModel.setFavorite("testmarkt", true)
        let afterChoosing = fixture.offers.requests
        #expect(afterChoosing > 0)

        await viewModel.refresh()
        #expect(fixture.offers.requests == afterChoosing)

        await viewModel.setFavorite("proefsuper", true)
        let afterSecondShop = fixture.offers.requests
        #expect(afterSecondShop > afterChoosing)

        clock.now += 7 * 3600
        await viewModel.refresh()
        let afterSevenHours = fixture.offers.requests
        #expect(afterSevenHours > afterSecondShop)

        await viewModel.refresh(force: true)
        #expect(fixture.offers.requests > afterSevenHours)
    }
}
