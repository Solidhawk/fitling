#if DEBUG
import Foundation
import FitlingCore

/// Sharing without a server: members and invitation codes in memory. `userID` is who is signed in, which the real
/// service takes from the session.
final class FakeListSharing: ListSharing, @unchecked Sendable {
    private let lock = NSLock()
    private let userID: UUID
    private var membersByList: [UUID: [ListMemberRecord]] = [:]
    private var codes: [String: UUID] = [:]
    private var _failure: SharingError?
    private var _withoutMaker: Set<UUID> = []
    private var _ownerFailure: SharingError?
    private var _joinsAfterNextLookup: UUID?

    init(userID: UUID) {
        self.userID = userID
    }

    /// Only adding an owner fails, as with a server error or an expired token while the rest answers.
    var ownerFailure: SharingError? {
        get { lock.withLock { _ownerFailure } }
        set { lock.withLock { _ownerFailure = newValue } }
    }

    /// This user joins that list (on another device) right after the next answer about their lists: that answer is
    /// already out of date when it arrives.
    var joinsAfterNextLookup: UUID? {
        get { lock.withLock { _joinsAfterNextLookup } }
        set { lock.withLock { _joinsAfterNextLookup = newValue } }
    }

    /// Lists whose maker left: the server no longer lets anyone become their owner (`created_by` is empty).
    var withoutMaker: Set<UUID> {
        get { lock.withLock { _withoutMaker } }
        set { lock.withLock { _withoutMaker = newValue } }
    }

    var failure: SharingError? {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }

    func addOwner(_ member: ListMemberRecord) async throws {
        try lock.withLock {
            if let failure = _failure ?? _ownerFailure { throw failure }
            if _withoutMaker.contains(member.listID) { throw SharingError.refused }
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

    func lists(of userID: UUID) async throws -> Set<UUID> {
        try lock.withLock {
            if let failure = _failure { throw failure }
            let answer = Set(membersByList.filter { list in list.value.contains { member in member.userID == userID } }.keys)
            if let joined = _joinsAfterNextLookup {
                _joinsAfterNextLookup = nil
                membersByList[joined, default: []].append(ListMemberRecord(listID: joined, userID: userID, role: "member", displayName: "Sam"))
            }
            return answer
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
            if !(membersByList[listID] ?? []).contains(where: { $0.userID == userID }) {
                membersByList[listID, default: []].append(ListMemberRecord(listID: listID, userID: userID, role: "member", displayName: name))
            }
            return listID
        }
    }

    func leave(_ listID: UUID, userID: UUID) async throws {
        lock.withLock { membersByList[listID]?.removeAll { $0.userID == userID } }
    }
}

/// Offers without a server: two test supermarkets, for the tests and the UI tests.
final class FakeOfferSource: OfferSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _offers: [OfferRecord] = []
    private var _rowCap = Int.max
    private var _failFromOffset: Int?
    private var _requests = 0
    private let shops = [SupermarketRecord(id: "testmarkt", name: "Testmarkt"), SupermarketRecord(id: "proefsuper", name: "Proefsuper")]

    var offerRecords: [OfferRecord] {
        get { lock.withLock { _offers } }
        set { lock.withLock { _offers = newValue } }
    }

    /// At most this many rows per request, like `max_rows` of Supabase's Data API.
    var rowCap: Int {
        get { lock.withLock { _rowCap } }
        set { lock.withLock { _rowCap = newValue } }
    }

    /// Requests from this offset on fail, like a connection that drops halfway.
    var failFromOffset: Int? {
        get { lock.withLock { _failFromOffset } }
        set { lock.withLock { _failFromOffset = newValue } }
    }

    /// How many times offers were asked for.
    var requests: Int { lock.withLock { _requests } }

    func supermarkets() async throws -> [SupermarketRecord] {
        shops
    }

    func offers(validFrom day: Day, supermarketIDs: [String], offset: Int, limit: Int) async throws -> [OfferRecord] {
        try lock.withLock {
            _requests += 1
            if let failFrom = _failFromOffset, offset >= failFrom { throw RemoteStoreError.network }
            let matching = _offers.filter { supermarketIDs.contains($0.supermarketID) && $0.validTo >= day }
            guard offset < matching.count else { return [] }
            return Array(matching[offset..<min(matching.count, offset + min(limit, _rowCap))])
        }
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
