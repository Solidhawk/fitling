#if DEBUG
import Foundation
import FitlingCore

/// Sharing without a server: members and invitation codes in memory.
final class FakeListSharing: ListSharing, @unchecked Sendable {
    private let lock = NSLock()
    private var membersByList: [UUID: [ListMemberRecord]] = [:]
    private var codes: [String: UUID] = [:]
    private var _failure: SharingError?

    var failure: SharingError? {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }

    func addOwner(_ member: ListMemberRecord) async throws {
        try lock.withLock {
            if let failure = _failure { throw failure }
            if !(membersByList[member.listID] ?? []).contains(where: { $0.userID == member.userID }) {
                membersByList[member.listID, default: []].append(member)
            }
        }
    }

    func members(of listID: UUID) async throws -> [ListMemberRecord] {
        try lock.withLock {
            if let failure = _failure { throw failure }
            return membersByList[listID] ?? []
        }
    }

    func createInvite(for listID: UUID) async throws -> String {
        try lock.withLock {
            if let failure = _failure { throw failure }
            let code = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))
            codes[code] = listID
            return code
        }
    }

    func join(code: String, name: String) async throws -> UUID {
        try lock.withLock {
            guard let listID = codes[code.uppercased()] else { throw SharingError.invalidInvite }
            return listID
        }
    }

    func leave(_ listID: UUID, userID: UUID) async throws {
        lock.withLock { membersByList[listID]?.removeAll { $0.userID == userID } }
    }
}

/// Two test supermarkets with a few offers: the backend has no offer source yet (UNFORGET).
final class FakeOfferSource: OfferSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _offers: [OfferRecord] = []
    private let shops = [SupermarketRecord(id: "testmarkt", name: "Testmarkt"), SupermarketRecord(id: "proefsuper", name: "Proefsuper")]

    var offerRecords: [OfferRecord] {
        get { lock.withLock { _offers } }
        set { lock.withLock { _offers = newValue } }
    }

    func supermarkets() async throws -> [SupermarketRecord] {
        shops
    }

    func offers(validFrom day: Day, supermarketIDs: [String]) async throws -> [OfferRecord] {
        lock.withLock { _offers.filter { supermarketIDs.contains($0.supermarketID) && $0.validTo >= day } }
    }

    /// Tomatoes and onions in both test supermarkets, valid for a week from `today`.
    static func sample(today: Day) -> [OfferRecord] {
        let end = today.adding(6)
        return [
            OfferRecord(
                id: UUID(), supermarketID: "testmarkt", externalID: "t1", title: "Tomatenblokjes 400 g", searchTitle: "tomatenblokjes",
                quantityValue: 400, quantityUnit: "g", priceCents: 79, validFrom: today, validTo: end
            ),
            OfferRecord(
                id: UUID(), supermarketID: "proefsuper", externalID: "p1", title: "Tomatenblokjes 400 g", searchTitle: "tomatenblokjes",
                quantityValue: 400, quantityUnit: "g", priceCents: 69, validFrom: today, validTo: end
            ),
            OfferRecord(
                id: UUID(), supermarketID: "testmarkt", externalID: "t2", title: "Uien 1 kg", searchTitle: "uien",
                quantityValue: 1000, quantityUnit: "g", priceCents: 119, validFrom: today, validTo: end
            ),
        ]
    }
}
#endif
