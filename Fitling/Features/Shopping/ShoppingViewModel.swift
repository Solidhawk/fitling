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
    private(set) var uncertain: [OfferMatch] = []
    private(set) var inviteCode: String?
    private(set) var sharingProblem: SharingError?

    let store: ShoppingStore
    private let menu: MenuStore
    private let services: ShoppingServices
    private let sync: SyncEngine
    private let defaults: UserDefaults
    private let listName: String
    private let ownerName: String

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
    }

    private var confirmedKey: String { "fitling.confirmedOffers" }

    /// Uncertain offers the user said are right; kept on this device only.
    var confirmed: Set<UUID> {
        Set((defaults.stringArray(forKey: confirmedKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    func reload() {
        let list = store.ensureList(named: listName, ownerName: ownerName)
        self.list = list
        items = store.items(of: list)
        members = store.members(of: list)
        let summary = store.offerSummary(for: list, confirmed: confirmed)
        cheapest = summary.perItem
        totals = summary.totals
        let accepted = summary.perItem
        let alreadyConfirmed = self.confirmed
        uncertain = summary.matches.filter { $0.confidence == .uncertain && !alreadyConfirmed.contains($0.offerID) && accepted[$0.itemID] == nil }
    }

    /// Sends and fetches the list, then the members and the offers.
    func refresh() async {
        _ = await sync.sync()
        for member in store.unsentMembers() {
            let record = ListMemberRecord(listID: member.listID, userID: member.userID, role: member.role, displayName: member.displayName)
            if (try? await services.sharing.addOwner(record)) != nil {
                member.needsPush = false
            }
        }
        try? store.context.save()
        for list in store.lists() {
            if let records = try? await services.sharing.members(of: list.id) {
                store.replaceMembers(of: list.id, with: records)
            }
        }
        await refreshOffers()
        reload()
    }

    func refreshOffers() async {
        guard let supermarkets = try? await services.offers.supermarkets() else { return }
        let offers = (try? await services.offers.offers(validFrom: store.today, supermarketIDs: store.favoriteSupermarketIDs())) ?? []
        store.store(supermarkets: supermarkets, offers: offers)
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
        store.fill(list, from: menu.entries(), menu: menu)
        reload()
    }

    func confirm(_ match: OfferMatch) {
        var ids = confirmed
        ids.insert(match.offerID)
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
        guard let list else { return }
        sharingProblem = nil
        await refresh()
        do {
            inviteCode = try await services.sharing.createInvite(for: list.id)
        } catch {
            sharingProblem = error as? SharingError ?? .rejected
        }
    }

    /// `name` is how the other members see this user, 1 to 40 characters.
    func join(code: String, name: String) async -> Bool {
        sharingProblem = nil
        let memberName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        do {
            _ = try await services.sharing.join(code: code.trimmingCharacters(in: .whitespacesAndNewlines), name: memberName.isEmpty ? ownerName : memberName)
            await refresh()
            return true
        } catch {
            sharingProblem = error as? SharingError ?? .rejected
            return false
        }
    }

    func leave() async {
        guard let list else { return }
        do {
            try await services.sharing.leave(list.id, userID: store.userID)
            store.forget(list)
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
