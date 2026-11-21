import Foundation
import Testing
@testable import FitlingCore

@Suite struct OfferMatcherTests {
    let today = day(2026, 11, 18)

    static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }

    func item(_ number: Int, _ name: String, brand: String? = nil, gtin: String? = nil, quantity: Double? = nil, unit: String? = nil) -> ListItemForMatching {
        ListItemForMatching(id: Self.id(number), name: name, brand: brand, gtin: gtin, quantity: quantity, unit: unit)
    }

    func offer(
        _ number: Int, _ title: String, store: String = "ah", brand: String? = nil, gtin: String? = nil,
        quantity: Double? = nil, unit: String? = nil, cents: Int = 199, from: Int = 16, to: Int = 22
    ) -> OfferForMatching {
        OfferForMatching(
            id: Self.id(number), supermarketID: store, title: title, brand: brand, gtin: gtin, quantityValue: quantity,
            quantityUnit: unit, priceCents: cents, validFrom: day(2026, 11, from), validTo: day(2026, 11, to)
        )
    }

    func match(_ item: ListItemForMatching, _ offer: OfferForMatching, ignoring: Set<String> = []) -> OfferMatch? {
        OfferMatcher.matches(items: [item], offers: [offer], on: today, ignoredWords: ignoring).first
    }

    // MARK: Words

    @Test func wordsDropCaseAccentsQuantitiesAndFillers() {
        #expect(OfferMatcher.words(in: "Crème fraîche 200 ml") == ["creme", "fraiche"])
        #expect(OfferMatcher.words(in: "De Halfvolle Melk, 1,5 l") == ["halfvolle", "melk"])
        #expect(OfferMatcher.words(in: "Eieren 6 stuks") == ["eieren"])
        #expect(OfferMatcher.words(in: "Gehakt 500g") == ["gehakt"])
        #expect(OfferMatcher.words(in: "AH Kipfilet", ignoring: ["ah"]) == ["kipfilet"])
        #expect(OfferMatcher.words(in: "7up 6x330 ml") == ["7up"])
    }

    // MARK: Certain

    @Test func sameBarcodeIsACertainMatch() {
        let result = match(item(1, "Pindakaas", gtin: "4006381333931"), offer(11, "Iets heel anders", gtin: "4006381333931"))
        #expect(result?.confidence == .certain)
        #expect(result?.offerID == Self.id(11))
        #expect(result?.priceCents == 199)
    }

    @Test func exactlyTheSameWordsAreACertainMatch() {
        #expect(match(item(1, "Halfvolle melk"), offer(11, "Halfvolle melk 1 l"))?.confidence == .certain)
        #expect(match(item(1, "crème fraîche"), offer(11, "CREME FRAICHE 200 ml"))?.confidence == .certain)
    }

    @Test func theShopNameInATitleDoesNotStandInTheWay() {
        #expect(match(item(1, "Kipfilet"), offer(11, "AH Kipfilet 500 g"), ignoring: ["ah"])?.confidence == .certain)
    }

    // MARK: Uncertain

    @Test func anOfferWithExtraWordsIsOnlyAPossibleMatch() {
        // "Melk" could be this, but chocolate milk says "melk" too: the user decides.
        #expect(match(item(1, "Melk"), offer(11, "Halfvolle melk 1 l"))?.confidence == .uncertain)
        #expect(match(item(1, "Melk"), offer(11, "Chocolade melk 1 l"))?.confidence == .uncertain)
    }

    @Test func aPartialNameMatchIsUncertain() {
        let result = match(item(1, "Volkoren pasta penne"), offer(11, "Pasta penne"))
        #expect(result?.confidence == .uncertain)
        #expect(abs((result?.score ?? 0) - 2.0 / 3.0) < 0.0001)
    }

    @Test func pluralStillMatches() {
        let result = match(item(1, "Tomaten"), offer(11, "Tomaat"))
        #expect(result?.confidence == .uncertain)
        #expect(result?.score == OfferMatcher.relatedWordScore)
    }

    // MARK: No match

    @Test func unrelatedNamesDoNotMatch() {
        #expect(match(item(1, "Pindakaas"), offer(11, "Pasta penne")) == nil)
        #expect(match(item(1, "Volkoren pasta penne rigate"), offer(11, "Pasta saus")) == nil)
        #expect(match(item(1, "Kip"), offer(11, "Kipfilet")) == nil)
    }

    @Test func anotherBrandIsNoMatch() {
        #expect(match(item(1, "Pindakaas", brand: "Calvé"), offer(11, "Pindakaas", brand: "Skippy")) == nil)
        #expect(match(item(1, "Pindakaas", brand: "Calvé"), offer(11, "Pindakaas", brand: "calve"))?.confidence == .certain)
        #expect(match(item(1, "Pindakaas", brand: "Calvé"), offer(11, "Pindakaas"))?.confidence == .certain)
    }

    @Test func theSameBrandLiftsAPartialMatch() {
        // One of two words is 0.5: too little on its own, enough with the brand.
        #expect(match(item(1, "Pindakaas naturel"), offer(11, "Pindakaas met stukjes noot")) == nil)
        let branded = match(item(1, "Pindakaas naturel", brand: "Calvé"), offer(11, "Pindakaas met stukjes noot", brand: "Calvé"))
        #expect(branded?.confidence == .uncertain)
        #expect(abs((branded?.score ?? 0) - 0.7) < 0.0001)
    }

    @Test func moreThanFourTimesTheQuantityIsNoMatch() {
        let mince = item(1, "Gehakt", quantity: 500, unit: "g")
        #expect(match(mince, offer(11, "Gehakt", quantity: 2500, unit: "g")) == nil)
        #expect(match(mince, offer(11, "Gehakt", quantity: 100, unit: "g")) == nil)
        #expect(match(mince, offer(11, "Gehakt", quantity: 2000, unit: "g"))?.confidence == .certain)
        // Without a quantity on one side, or with another unit, the quantity says nothing.
        #expect(match(mince, offer(11, "Gehakt"))?.confidence == .certain)
        #expect(match(mince, offer(11, "Gehakt", quantity: 4, unit: "piece"))?.confidence == .certain)
    }

    @Test func offersOutsideTheirDatesAreIgnored() {
        #expect(match(item(1, "Melk"), offer(11, "Melk", from: 10, to: 17)) == nil)
        #expect(match(item(1, "Melk"), offer(11, "Melk", from: 19, to: 25)) == nil)
        #expect(match(item(1, "Melk"), offer(11, "Melk", from: 18, to: 18))?.confidence == .certain)
    }

    // MARK: Order and totals

    @Test func bestMatchComesFirstPerItemInTheOrderOfTheList() {
        let items = [item(1, "Melk"), item(2, "Brood")]
        let offers = [
            offer(11, "Halfvolle melk", cents: 99),
            offer(12, "Melk", store: "jumbo", cents: 129),
            offer(13, "Melk", cents: 119),
            offer(14, "Brood", cents: 189),
        ]
        let result = OfferMatcher.matches(items: items, offers: offers, on: today)
        #expect(result.map(\.offerID) == [Self.id(13), Self.id(12), Self.id(11), Self.id(14)])
        #expect(result.map(\.itemID) == [Self.id(1), Self.id(1), Self.id(1), Self.id(2)])
    }

    @Test func cheapestPerItemCountsOnlyCertainAndConfirmedMatches() {
        let offers = [offer(11, "Melk", cents: 129), offer(12, "Halfvolle melk", store: "jumbo", cents: 99)]
        let result = OfferMatcher.matches(items: [item(1, "Melk")], offers: offers, on: today)

        #expect(OfferMatcher.cheapestPerItem(result, confirmedOfferIDs: [])[Self.id(1)]?.offerID == Self.id(11))
        #expect(OfferMatcher.cheapestPerItem(result, confirmedOfferIDs: [Self.id(12)])[Self.id(1)]?.offerID == Self.id(12))
    }

    @Test func storeTotalsShowWhatAShopHasNoPriceFor() {
        let items = [item(1, "Melk"), item(2, "Brood")]
        let offers = [
            offer(11, "Melk", cents: 129),
            offer(12, "Melk", store: "jumbo", cents: 139),
            offer(13, "Brood", store: "jumbo", cents: 189),
            offer(14, "Volkoren brood", cents: 149),
        ]
        let result = OfferMatcher.matches(items: items, offers: offers, on: today)
        let totals = OfferMatcher.storeTotals(itemIDs: items.map(\.id), matches: result, confirmedOfferIDs: [])
        #expect(totals == [
            StoreTotal(supermarketID: "jumbo", totalCents: 328, itemsWithoutPrice: 0),
            StoreTotal(supermarketID: "ah", totalCents: 129, itemsWithoutPrice: 1),
        ])

        let confirmed = OfferMatcher.storeTotals(itemIDs: items.map(\.id), matches: result, confirmedOfferIDs: [Self.id(14)])
        #expect(confirmed == [
            StoreTotal(supermarketID: "ah", totalCents: 278, itemsWithoutPrice: 0),
            StoreTotal(supermarketID: "jumbo", totalCents: 328, itemsWithoutPrice: 0),
        ])
    }

    /// A total of € 0,00 for a shop with only possible offers says nothing (UNFORGET S24).
    @Test func aShopWithOnlyPossibleOffersGetsNoTotal() {
        let items = [item(1, "Tomaat"), item(2, "Brood")]
        let offers = [offer(11, "Tomatenblokjes", cents: 79), offer(12, "Tomatenblokjes", store: "jumbo", cents: 69)]
        let result = OfferMatcher.matches(items: items, offers: offers, on: today)
        #expect(OfferMatcher.storeTotals(itemIDs: items.map(\.id), matches: result, confirmedOfferIDs: []).isEmpty)
        #expect(OfferMatcher.storeTotals(itemIDs: items.map(\.id), matches: result, confirmedOfferIDs: [Self.id(12)]) == [
            StoreTotal(supermarketID: "jumbo", totalCents: 69, itemsWithoutPrice: 1),
        ])
    }
}

@Suite struct SyncRulesTests {
    let noon = Date(timeIntervalSince1970: 1_795_000_000)

    func local(minutes: Double, needsPush: Bool) -> LocalRowState {
        LocalRowState(updatedAt: noon.addingTimeInterval(minutes * 60), needsPush: needsPush)
    }

    func remote(minutes: Double, deleted: Bool = false) -> RemoteRowState {
        RemoteRowState(updatedAt: noon.addingTimeInterval(minutes * 60), isDeleted: deleted)
    }

    @Test func aRowTheDeviceDoesNotHaveIsAdded() {
        #expect(SyncRules.pullAction(local: nil, remote: remote(minutes: 0)) == .insert)
    }

    @Test func aDeletionOfARowTheDeviceNeverHadIsIgnored() {
        #expect(SyncRules.pullAction(local: nil, remote: remote(minutes: 0, deleted: true)) == .ignore)
    }

    @Test func theServerWinsOverARowWithoutLocalChanges() {
        #expect(SyncRules.pullAction(local: local(minutes: 0, needsPush: false), remote: remote(minutes: 5)) == .overwrite)
        // Also when the server's version looks older: without a pending change the device has nothing to defend.
        #expect(SyncRules.pullAction(local: local(minutes: 5, needsPush: false), remote: remote(minutes: 0)) == .overwrite)
    }

    @Test func aNewerLocalChangeIsKept() {
        #expect(SyncRules.pullAction(local: local(minutes: 5, needsPush: true), remote: remote(minutes: 0)) == .keepLocal)
        #expect(SyncRules.pullAction(local: local(minutes: 5, needsPush: true), remote: remote(minutes: 0, deleted: true)) == .keepLocal)
    }

    @Test func anOlderLocalChangeLosesToTheServer() {
        #expect(SyncRules.pullAction(local: local(minutes: 0, needsPush: true), remote: remote(minutes: 5)) == .overwrite)
        #expect(SyncRules.pullAction(local: local(minutes: 0, needsPush: true), remote: remote(minutes: 0)) == .overwrite)
    }

    @Test func aDeletionOnTheServerRemovesTheLocalRow() {
        #expect(SyncRules.pullAction(local: local(minutes: 0, needsPush: false), remote: remote(minutes: 5, deleted: true)) == .deleteLocal)
        #expect(SyncRules.pullAction(local: local(minutes: 0, needsPush: true), remote: remote(minutes: 5, deleted: true)) == .deleteLocal)
    }

    @Test func theFirstPullFetchesEverything() {
        #expect(SyncRules.pullStart(cursor: nil, lastPull: nil, now: noon) == .everything)
    }

    @Test func aTableThatWasEmptyLastTimeIsFetchedWhole() {
        #expect(SyncRules.pullStart(cursor: nil, lastPull: noon.addingTimeInterval(-3600), now: noon) == .everything)
    }

    @Test func aLaterPullStartsFiveMinutesBeforeTheCursor() {
        let cursor = noon.addingTimeInterval(-3600)
        #expect(SyncRules.pullStart(cursor: cursor, lastPull: cursor, now: noon) == .since(cursor.addingTimeInterval(-300)))
    }

    @Test func aDeviceThatDidNotPullForNinetyDaysStartsOver() {
        let ninetyDays: TimeInterval = 90 * 24 * 60 * 60
        let cursor = noon.addingTimeInterval(-ninetyDays - 3600)
        #expect(SyncRules.pullStart(cursor: cursor, lastPull: noon.addingTimeInterval(-ninetyDays - 1), now: noon) == .resetThenEverything)
        #expect(SyncRules.pullStart(cursor: cursor, lastPull: noon.addingTimeInterval(-ninetyDays), now: noon) == .since(cursor.addingTimeInterval(-300)))
        #expect(SyncRules.pullStart(cursor: nil, lastPull: noon.addingTimeInterval(-ninetyDays - 1), now: noon) == .resetThenEverything)
    }

    /// The 90 days count from the last pull, not from the last change: a table nobody touches
    /// must not be cleared and fetched again on every round.
    @Test func aQuietTableIsNotStartedOver() {
        let longAgo = noon.addingTimeInterval(-200 * 24 * 60 * 60)
        let yesterday = noon.addingTimeInterval(-24 * 60 * 60)
        #expect(SyncRules.pullStart(cursor: longAgo, lastPull: yesterday, now: noon) == .since(longAgo.addingTimeInterval(-300)))
    }

    @Test func theCursorMovesToTheNewestRowAndNeverBack() {
        let earlier = noon.addingTimeInterval(-60)
        let later = noon.addingTimeInterval(60)
        #expect(SyncRules.nextCursor(current: nil, pageSyncedAt: []) == nil)
        #expect(SyncRules.nextCursor(current: nil, pageSyncedAt: [earlier, later, noon]) == later)
        #expect(SyncRules.nextCursor(current: noon, pageSyncedAt: [earlier]) == noon)
        #expect(SyncRules.nextCursor(current: noon, pageSyncedAt: []) == noon)
    }

    @Test func thePushFlagIsOnlyClearedWhenTheRowDidNotChangeMeanwhile() {
        #expect(SyncRules.canClearPushFlag(sentUpdatedAt: noon, currentUpdatedAt: noon))
        #expect(SyncRules.canClearPushFlag(sentUpdatedAt: noon, currentUpdatedAt: noon.addingTimeInterval(1)) == false)
    }

    @Test func batchSizesMatchTheArchitecture() {
        #expect(SyncRules.pushBatchSize == 200)
        #expect(SyncRules.pullPageSize == 500)
        #expect(SyncRules.pullOverlap == 300)
    }
}
