import Foundation

public struct ListItemForMatching: Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var brand: String?
    public var gtin: String?
    public var quantity: Double?
    /// "g", "ml" or "piece".
    public var unit: String?

    public init(id: UUID, name: String, brand: String? = nil, gtin: String? = nil, quantity: Double? = nil, unit: String? = nil) {
        self.id = id
        self.name = name
        self.brand = brand
        self.gtin = gtin
        self.quantity = quantity
        self.unit = unit
    }
}

public struct OfferForMatching: Sendable, Equatable {
    public var id: UUID
    public var supermarketID: String
    public var title: String
    public var brand: String?
    public var gtin: String?
    public var quantityValue: Double?
    public var quantityUnit: String?
    public var priceCents: Int
    public var validFrom: Day
    public var validTo: Day

    public init(
        id: UUID, supermarketID: String, title: String, brand: String? = nil, gtin: String? = nil,
        quantityValue: Double? = nil, quantityUnit: String? = nil, priceCents: Int, validFrom: Day, validTo: Day
    ) {
        self.id = id
        self.supermarketID = supermarketID
        self.title = title
        self.brand = brand
        self.gtin = gtin
        self.quantityValue = quantityValue
        self.quantityUnit = quantityUnit
        self.priceCents = priceCents
        self.validFrom = validFrom
        self.validTo = validTo
    }
}

public enum MatchConfidence: Sendable, Equatable {
    /// Same barcode, or exactly the same words. Counts in the totals straight away.
    case certain
    /// Shown as "possibly on offer"; counts only after the user confirmed it.
    case uncertain
}

public struct OfferMatch: Sendable, Equatable {
    public var itemID: UUID
    public var offerID: UUID
    public var supermarketID: String
    public var priceCents: Int
    public var confidence: MatchConfidence
    public var score: Double
}

public struct StoreTotal: Sendable, Equatable {
    public var supermarketID: String
    public var totalCents: Int
    /// Items this shop has no usable offer for. The app never invents a regular price.
    public var itemsWithoutPrice: Int
}

/// Matches shopping-list items with offers by barcode or by words. Deliberately simple, so
/// every match can be explained: "these words were the same".
public enum OfferMatcher {
    public static let uncertainScore = 0.6
    public static let relatedWordScore = 0.75
    public static let brandBonus = 0.2
    /// An offer with more than this many times the quantity (or less than one over it) is another product.
    public static let largestQuantityFactor = 4.0
    public static let shortestRelatedWord = 4

    /// The words that carry meaning: lower case, no accents, no quantities, units or filler words.
    public static func words(in text: String, ignoring ignoredWords: Set<String> = []) -> [String] {
        []
    }

    /// Every offer that fits an item on `day`, best first per item, in the order of `items`.
    /// `ignoredWords` are words that say nothing about the product, such as the shop's name.
    public static func matches(
        items: [ListItemForMatching], offers: [OfferForMatching], on day: Day, ignoredWords: Set<String> = []
    ) -> [OfferMatch] {
        []
    }

    /// The cheapest offer per item, from certain matches and the uncertain ones the user confirmed.
    public static func cheapestPerItem(_ matches: [OfferMatch], confirmedOfferIDs: Set<UUID>) -> [UUID: OfferMatch] {
        [:]
    }

    /// What the list costs per shop, counting only usable matches, and how many items each shop
    /// has no price for. Fewest missing items first, then cheapest.
    public static func storeTotals(itemIDs: [UUID], matches: [OfferMatch], confirmedOfferIDs: Set<UUID>) -> [StoreTotal] {
        []
    }
}
