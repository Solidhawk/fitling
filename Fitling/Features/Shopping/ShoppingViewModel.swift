import Foundation
import Observation
import SwiftData
import FitlingCore

/// Where the shopping list gets its sharing and offers from: Supabase in the app, fakes in the tests.
struct ShoppingServices {
    let sharing: any ListSharing
    let offers: any OfferSource
}

/// The shopping list: items in the order of the shop, what the menu needs, sharing with an
/// invitation code, and the offers of the favourite supermarkets.
@Observable
@MainActor
final class ShoppingViewModel {
    private(set) var list: ShoppingList?
    private(set) var items: [ShoppingItem] = []
    private(set) var members: [ShoppingListMember] = []
    private(set) var cheapest: [UUID: OfferMatch] = [:]
    private(set) var totals: [StoreTotal] = []
    private(set) var questions: [OfferQuestion] = []
    private(set) var inviteCode: String?
    private(set) var sharingProblem: SharingError?
    /// Why a code did not work, shown in the sheet it was typed in (UNFORGET S48).
    private(set) var joinProblem: SharingError?

    let store: ShoppingStore
    private let menu: MenuStore
    private let services: ShoppingServices
    private let sync: SyncEngine
    private let defaults: UserDefaults
    private let listName: String
    private let ownerName: String
    private let now: () -> Date

    /// Rows asked for per request. Supabase's Data API sends at most `max_rows` (1,000 by default) whatever is
    /// asked, so paging goes on until a page comes back empty.
    static let offerPageSize = 1_000
    /// The offers change once a night; until they are this old, opening the list keeps the ones on the device.
    static let offersKeptFor: TimeInterval = 6 * 3600

    init(
        profile: UserProfile, sync: SyncEngine, services: ShoppingServices, defaults: UserDefaults = .standard,
        listName: String, ownerName: String, timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init
    ) {
        store = ShoppingStore(context: sync.context, userID: profile.id, timeZone: timeZone, now: now)
        menu = MenuStore(context: sync.context, profile: profile, timeZone: timeZone, now: now)
        self.services = services
        self.sync = sync
        self.defaults = defaults
        self.listName = listName
        self.ownerName = ownerName
        self.now = now
    }

    private var confirmedKey: String { "fitling.confirmedOffers" }
    /// The supermarkets the offers on the device were fetched for.
    private var offerShopsKey: String { "fitling.offerShops" }
    /// The list this user joined last on this device. It shows instead of the first by name, which with two lists
    /// called the same is either (UNFORGET S47). Kept until the user leaves it: while it is not on the device yet, the
    /// first list shows.
    private var joinedListKey: String { "fitling.shoppingList.\(store.userID.uuidString)" }

    private var joinedList: UUID? {
        defaults.string(forKey: joinedListKey).flatMap(UUID.init(uuidString:))
    }

    /// Uncertain offers the user said are right; kept on this device only.
    var confirmed: Set<UUID> {
        Set((defaults.stringArray(forKey: confirmedKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    func reload() {
        let list = store.ensureList(named: listName, ownerName: ownerName, preferred: joinedList)
        self.list = list
        items = store.items(of: list)
        members = store.members(of: list)
        let summary = store.offers(for: list, confirmed: confirmed)
        cheapest = summary.cheapest
        totals = summary.totals
        questions = summary.questions
    }

    /// Sends and fetches the list, then the members and the offers.
    func refresh(force: Bool = false) async {
        let synced = await sync.sync() == .completed
        await sendOwners()
        await followMemberships(syncAgain: synced)
        // By id, and looked up again after each request: another refresh or leaving may have removed a list meanwhile.
        for listID in store.lists().map(\.id) {
            guard let records = try? await services.sharing.members(of: listID), store.list(listID) != nil else { continue }
            store.replaceMembers(of: listID, with: records)
        }
        await refreshOffers(force: force)
        reload()
    }

    /// The owner rows made on this device. As records first: leaving may remove a row while a request is under way.
    private func sendOwners() async {
        let unsent = store.unsentMembers().map {
            ListMemberRecord(listID: $0.listID, userID: $0.userID, role: $0.role, displayName: $0.displayName)
        }
        for record in unsent {
            guard (try? await services.sharing.addOwner(record)) != nil else { continue }
            let sent = store.unsentMembers().first { $0.listID == record.listID && $0.userID == record.userID }
            sent?.needsPush = false
        }
        try? store.context.save()
    }

    /// Which lists the server counts this user as a member of. A list joined elsewhere (the web app, another device)
    /// can be older than what this device last fetched, so the lists and their items are fetched whole. A list left
    /// elsewhere, or gone with its last member, the server says nothing more about: it goes from this device, unless
    /// the list or its owner still waits to be sent. `syncAgain`: the round before reached the server, so another one
    /// now brings the lists; otherwise the next round fetches them whole.
    private func followMemberships(syncAgain: Bool) async {
        guard let memberships = try? await services.sharing.lists(of: store.userID) else { return }
        if !memberships.isSubset(of: store.knownListIDs()) {
            sync.pullWhole([ShoppingList.tableName, ShoppingItem.tableName])
            if syncAgain { _ = await sync.sync() }
        }
        for listID in store.lists().map(\.id) where !memberships.contains(listID) {
            guard let list = store.list(listID), !list.needsPush,
                  !store.members(of: list).contains(where: { $0.userID == store.userID && $0.needsPush }) else { continue }
            await notAMember(of: list)
        }
    }

    /// A list this user made elsewhere before it had its owner gets one, as on the web (ensureList in
    /// web/src/data/shopping.ts). Any other goes from this device, and so does this one when the server refuses.
    private func notAMember(of list: ShoppingList) async {
        let listID = list.id
        if list.createdBy == store.userID {
            let owner = ListMemberRecord(listID: listID, userID: store.userID, role: "owner", displayName: ownerName)
            do {
                try await services.sharing.addOwner(owner)
                return
            } catch SharingError.refused {
                // The server emptied `created_by` when this user left, or the list is gone.
            } catch {
                // No answer about the list itself: asked again next time.
                return
            }
        }
        // Asked once more right before: a join can have finished while this refresh was waiting on the server.
        guard let memberships = try? await services.sharing.lists(of: store.userID), !memberships.contains(listID) else { return }
        if joinedList == listID { defaults.removeObject(forKey: joinedListKey) }
        if let current = store.list(listID) { store.forget(current) }
        // Right away: the list and items on screen may be the ones just removed.
        reload()
    }

    /// Fetches the offers of the favourite supermarkets, page by page. Without `force` it keeps the ones on the
    /// device while they are fresh and for the same supermarkets.
    func refreshOffers(force: Bool = false) async {
        let shops = store.favoriteSupermarketIDs()
        if !force, defaults.stringArray(forKey: offerShopsKey) == shops,
           let fetched = store.offersFetchedAt(), now().timeIntervalSince(fetched) < Self.offersKeptFor {
            return
        }
        guard let supermarkets = try? await services.offers.supermarkets() else { return }
        var offers: [OfferRecord] = []
        do {
            while true {
                let page = try await services.offers.offers(
                    validFrom: store.today, supermarketIDs: shops, offset: offers.count, limit: Self.offerPageSize
                )
                if page.isEmpty { break }
                offers += page
            }
        } catch {
            // Half the offers would hide cheaper ones; the ones on the device stay until all pages arrive.
            return
        }
        store.store(supermarkets: supermarkets, offers: offers)
        defaults.set(shops, forKey: offerShopsKey)
    }

    func add(_ name: String) {
        guard let list else { return }
        store.add(name, to: list)
        reload()
    }

    func toggle(_ item: ShoppingItem) {
        store.toggle(item)
        reload()
    }

    func remove(_ item: ShoppingItem) {
        store.remove(item)
        reload()
    }

    func clearChecked() {
        guard let list else { return }
        store.clearChecked(of: list)
        reload()
    }

    /// What this week's menu needs.
    func fillFromMenu() {
        guard let list else { return }
        store.fill(list, menu: menu)
        reload()
    }

    func confirm(_ question: OfferQuestion) {
        var ids = confirmed
        ids.formUnion(question.offerIDs)
        defaults.set(ids.map(\.uuidString).sorted(), forKey: confirmedKey)
        reload()
    }

    func setFavorite(_ supermarketID: String, _ isFavorite: Bool) async {
        store.setFavorite(supermarketID, isFavorite)
        await refreshOffers()
        reload()
    }

    // MARK: Sharing

    func createInvite() async {
        guard let listID = list?.id else { return }
        sharingProblem = nil
        await refresh()
        do {
            inviteCode = try await services.sharing.createInvite(for: listID)
        } catch {
            sharingProblem = error as? SharingError ?? .rejected
        }
    }

    /// `name` is how the other members see this user, 1 to 40 characters. The list of the code shows from then on.
    func join(code: String, name: String) async -> Bool {
        sharingProblem = nil
        joinProblem = nil
        let memberName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        do {
            let listID = try await services.sharing.join(
                code: code.trimmingCharacters(in: .whitespacesAndNewlines), name: memberName.isEmpty ? ownerName : memberName
            )
            defaults.set(listID.uuidString, forKey: joinedListKey)
            // The list and its items can be older than what this device last fetched.
            sync.pullWhole([ShoppingList.tableName, ShoppingItem.tableName])
            await refresh()
            return true
        } catch {
            joinProblem = error as? SharingError ?? .rejected
            return false
        }
    }

    /// The sheet closed: its problem goes with it.
    func dismissJoinProblem() {
        joinProblem = nil
    }

    func leave() async {
        guard let listID = list?.id else { return }
        do {
            try await services.sharing.leave(listID, userID: store.userID)
            if joinedList == listID { defaults.removeObject(forKey: joinedListKey) }
            // A refresh during the request may already have removed it.
            if let current = store.list(listID) { store.forget(current) }
            self.list = nil
            reload()
        } catch {
            sharingProblem = error as? SharingError ?? .rejected
        }
    }

    func dismissInvite() {
        inviteCode = nil
    }

    func supermarketName(_ id: String) -> String {
        store.supermarkets().first { $0.id == id }?.name ?? id
    }
}
