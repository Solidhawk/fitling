import Foundation
import Supabase
import FitlingCore

/// One member of a shared list, as `shopping_list_members` holds it.
struct ListMemberRecord: Codable, Equatable, Sendable {
    var listID: UUID
    var userID: UUID
    var role: String
    var displayName: String

    enum CodingKeys: String, CodingKey {
        case role
        case listID = "list_id"
        case userID = "user_id"
        case displayName = "display_name"
    }
}

/// Members and invitations of shared lists (TASKS 6.3). Members have no `synced_at`, so they do
/// not go through the sync engine; joining only works with an invitation code (D-18).
protocol ListSharing: Sendable {
    /// The maker of a list adds themselves as its owner, once the list is on the server.
    func addOwner(_ member: ListMemberRecord) async throws
    func members(of listID: UUID) async throws -> [ListMemberRecord]
    /// A code that is valid for seven days and shown only once.
    func createInvite(for listID: UUID) async throws -> String
    /// Returns the id of the list joined.
    func join(code: String, name: String) async throws -> UUID
    func leave(_ listID: UUID, userID: UUID) async throws
}

/// What can go wrong with sharing, in terms the screen can explain.
enum SharingError: Error, Equatable {
    case network
    case invalidInvite
    case listFull
    case rejected
}

struct SupabaseListSharing: ListSharing {
    let client: SupabaseClient

    /// A plain insert, and "already a member" (23505) is fine: an upsert (ON CONFLICT) also needs the read policy to let
    /// the new row through, and that policy asks for the membership this row is only now giving. Found by the web's
    /// tests against a real Supabase (web phase 6).
    func addOwner(_ member: ListMemberRecord) async throws {
        _ = try await run {
            do {
                try await client.from("shopping_list_members").insert(member, returning: .minimal).execute()
            } catch let error as PostgrestError where error.code == "23505" {}
        }
    }

    func members(of listID: UUID) async throws -> [ListMemberRecord] {
        try await run { try await client.from("shopping_list_members").select().eq("list_id", value: listID).execute().value }
    }

    func createInvite(for listID: UUID) async throws -> String {
        try await run { try await client.rpc("create_shopping_list_invite", params: ["list": listID]).execute().value }
    }

    func join(code: String, name: String) async throws -> UUID {
        try await run { try await client.rpc("join_shopping_list", params: ["invite_code": code, "member_name": name]).execute().value }
    }

    func leave(_ listID: UUID, userID: UUID) async throws {
        _ = try await run { try await client.from("shopping_list_members").delete().eq("list_id", value: listID).eq("user_id", value: userID).execute() }
    }

    private func run<Value>(_ work: () async throws -> Value) async throws -> Value {
        do {
            return try await work()
        } catch is URLError {
            throw SharingError.network
        } catch {
            let text = String(describing: error)
            if text.contains("invalid_invite") { throw SharingError.invalidInvite }
            if text.contains("list_full") { throw SharingError.listFull }
            throw SharingError.rejected
        }
    }
}

/// The offers and supermarkets the backend collected. Read only (TASKS 6.4, 6.7).
struct OfferRecord: Codable, Equatable, Sendable {
    var id: UUID
    var supermarketID: String
    var externalID: String
    var title: String
    var searchTitle: String
    var brand: String?
    var gtin: String?
    var quantityValue: Double?
    var quantityUnit: String?
    var priceCents: Int
    var regularPriceCents: Int?
    var promoLabel: String?
    var validFrom: Day
    var validTo: Day
    var imageURL: String?

    enum CodingKeys: String, CodingKey {
        case id, title, brand, gtin
        case supermarketID = "supermarket_id"
        case externalID = "external_id"
        case searchTitle = "search_title"
        case quantityValue = "quantity_value"
        case quantityUnit = "quantity_unit"
        case priceCents = "price_cents"
        case regularPriceCents = "regular_price_cents"
        case promoLabel = "promo_label"
        case validFrom = "valid_from"
        case validTo = "valid_to"
        case imageURL = "image_url"
    }
}

struct SupermarketRecord: Codable, Equatable, Sendable {
    var id: String
    var name: String
}

protocol OfferSource: Sendable {
    func supermarkets() async throws -> [SupermarketRecord]
    /// One page of the offers still valid on `day` or later, of the given supermarkets, in a fixed order.
    /// The server may send fewer than `limit` rows; only an empty page means there are no more.
    func offers(validFrom day: Day, supermarketIDs: [String], offset: Int, limit: Int) async throws -> [OfferRecord]
}

struct SupabaseOfferSource: OfferSource {
    let client: SupabaseClient

    func supermarkets() async throws -> [SupermarketRecord] {
        do {
            return try await client.from("supermarkets").select("id,name").order("name").execute().value
        } catch is URLError {
            throw RemoteStoreError.network
        }
    }

    func offers(validFrom day: Day, supermarketIDs: [String], offset: Int, limit: Int) async throws -> [OfferRecord] {
        guard !supermarketIDs.isEmpty else { return [] }
        do {
            return try await client.from("offers").select()
                .in("supermarket_id", values: supermarketIDs)
                .gte("valid_to", value: day.isoString)
                // PrijsProfeet's terms: a price shown as current is at most a day old. The job runs
                // nightly; an offer it did not refresh stays out of sight.
                .gte("fetched_at", value: Date.now.addingTimeInterval(-26 * 3600).ISO8601Format())
                // A fixed order, so pages neither skip nor repeat an offer.
                .order("id")
                .range(from: offset, to: offset + limit - 1)
                .execute()
                .value
        } catch is URLError {
            throw RemoteStoreError.network
        }
    }
}
