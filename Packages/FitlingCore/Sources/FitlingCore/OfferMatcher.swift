#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

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
        let ignored = Set(ignoredWords.map { plain($0) })
        return plain(text)
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
            .filter { word in
                word.count > 1 && !isQuantity(word) && !units.contains(word) && !fillers.contains(word) && !ignored.contains(word)
            }
    }

    /// Every offer that fits an item on `day`, best first per item, in the order of `items`.
    /// `ignoredWords` are words that say nothing about the product, such as the shop's name.
    public static func matches(
        items: [ListItemForMatching], offers: [OfferForMatching], on day: Day, ignoredWords: Set<String> = []
    ) -> [OfferMatch] {
        let valid = offers
            .filter { $0.validFrom <= day && day <= $0.validTo }
            .map { ReadOffer($0, ignoring: ignoredWords) }
        return items.flatMap { item in
            let read = ReadItem(item, ignoring: ignoredWords)
            return valid
                .compactMap { match(read, $0) }
                .sorted { first, second in
                    if first.confidence != second.confidence { return first.confidence == .certain }
                    if first.score != second.score { return first.score > second.score }
                    if first.priceCents != second.priceCents { return first.priceCents < second.priceCents }
                    return first.offerID.uuidString < second.offerID.uuidString
                }
        }
    }

    /// The cheapest offer per item, from certain matches and the uncertain ones the user confirmed.
    public static func cheapestPerItem(_ matches: [OfferMatch], confirmedOfferIDs: Set<UUID>) -> [UUID: OfferMatch] {
        var cheapest: [UUID: OfferMatch] = [:]
        for match in matches where isUsable(match, confirmedOfferIDs: confirmedOfferIDs) {
            if let current = cheapest[match.itemID], !isCheaper(match, than: current) { continue }
            cheapest[match.itemID] = match
        }
        return cheapest
    }

    /// What the list costs per shop, counting only usable matches, and how many items each shop
    /// has no price for. A shop without a single price has no total. Fewest missing items first, then cheapest.
    public static func storeTotals(itemIDs: [UUID], matches: [OfferMatch], confirmedOfferIDs: Set<UUID>) -> [StoreTotal] {
        Set(matches.map(\.supermarketID))
            .compactMap { store -> StoreTotal? in
                let cheapest = cheapestPerItem(matches.filter { $0.supermarketID == store }, confirmedOfferIDs: confirmedOfferIDs)
                let priced = itemIDs.compactMap { cheapest[$0]?.priceCents }
                guard !priced.isEmpty else { return nil }
                return StoreTotal(supermarketID: store, totalCents: priced.reduce(0, +), itemsWithoutPrice: itemIDs.count - priced.count)
            }
            .sorted { ($0.itemsWithoutPrice, $0.totalCents, $0.supermarketID) < ($1.itemsWithoutPrice, $1.totalCents, $1.supermarketID) }
    }

    // MARK: One item against one offer

    /// An item with its words read once. Reading words is the slow part, and one list meets thousands of
    /// offers (Albert Heijn alone has over 5,000; UNFORGET S23).
    private struct ReadItem {
        let item: ListItemForMatching
        let brand: [String]
        let words: [String]
        let wordSet: Set<String>

        init(_ item: ListItemForMatching, ignoring ignoredWords: Set<String>) {
            self.item = item
            brand = item.brand.map { OfferMatcher.words(in: $0) } ?? []
            words = OfferMatcher.words(in: item.name, ignoring: ignoredWords)
            wordSet = Set(words)
        }
    }

    /// An offer with its words read once.
    private struct ReadOffer {
        let offer: OfferForMatching
        let brand: [String]
        let words: [String]
        let wordSet: Set<String>

        init(_ offer: OfferForMatching, ignoring ignoredWords: Set<String>) {
            self.offer = offer
            brand = offer.brand.map { OfferMatcher.words(in: $0) } ?? []
            words = OfferMatcher.words(in: offer.title, ignoring: ignoredWords)
            wordSet = Set(words)
        }
    }

    private static func match(_ read: ReadItem, _ readOffer: ReadOffer) -> OfferMatch? {
        let item = read.item
        let offer = readOffer.offer
        func result(_ confidence: MatchConfidence, _ score: Double) -> OfferMatch {
            OfferMatch(
                itemID: item.id, offerID: offer.id, supermarketID: offer.supermarketID,
                priceCents: offer.priceCents, confidence: confidence, score: score
            )
        }
        if let gtin = item.gtin, gtin == offer.gtin { return result(.certain, 1) }

        let itemBrand = read.brand
        let offerBrand = readOffer.brand
        if !itemBrand.isEmpty, !offerBrand.isEmpty, itemBrand != offerBrand { return nil }
        if isOtherSize(item, offer) { return nil }

        let itemWords = read.words
        let offerWords = readOffer.words
        guard !itemWords.isEmpty else { return nil }
        if read.wordSet == readOffer.wordSet { return result(.certain, 1) }

        var found = 0.0
        for word in itemWords {
            if readOffer.wordSet.contains(word) {
                found += 1
            } else if offerWords.contains(where: { isRelated(word, $0) }) {
                found += relatedWordScore
            }
        }
        var score = found / Double(itemWords.count)
        let sameBrand = !itemBrand.isEmpty && (itemBrand == offerBrand || itemBrand.allSatisfy { readOffer.wordSet.contains($0) })
        if sameBrand { score += brandBonus }
        // Rounded so that 0.5 + 0.2 does not fall just short of a threshold.
        score = min((score * 1_000_000).rounded() / 1_000_000, 1)
        return score >= uncertainScore ? result(.uncertain, score) : nil
    }

    /// Both say how much is in the pack, in the same unit, and one is more than four times the other.
    private static func isOtherSize(_ item: ListItemForMatching, _ offer: OfferForMatching) -> Bool {
        guard let wanted = item.quantity, let offered = offer.quantityValue, wanted > 0, offered > 0,
              let unit = item.unit, unit == offer.quantityUnit else { return false }
        return max(wanted, offered) / min(wanted, offered) > largestQuantityFactor
    }

    /// Plural and singular, or a word and a slightly longer form of it: the first letters are
    /// the same and at most the last two of the shorter word differ.
    private static func isRelated(_ first: String, _ second: String) -> Bool {
        let shorter = min(first.count, second.count)
        guard shorter >= shortestRelatedWord else { return false }
        let shared = zip(first, second).prefix { $0 == $1 }.count
        return shared >= max(shortestRelatedWord, shorter - 2)
    }

    private static func isUsable(_ match: OfferMatch, confirmedOfferIDs: Set<UUID>) -> Bool {
        match.confidence == .certain || confirmedOfferIDs.contains(match.offerID)
    }

    private static func isCheaper(_ match: OfferMatch, than other: OfferMatch) -> Bool {
        (match.priceCents, match.offerID.uuidString) < (other.priceCents, other.offerID.uuidString)
    }

    // MARK: Words

    private static let units: Set<String> = ["g", "gr", "gram", "kg", "kilo", "ml", "cl", "l", "liter", "stuks", "stuk", "st", "x", "pak", "per"]
    private static let fillers: Set<String> = ["de", "het", "een", "van", "met", "en", "voor"]

    /// Lower case and without accents: "Crème" and "creme" are the same word.
    private static func plain(_ text: String) -> String {
        text.folded
    }

    /// "500", "500g", "6x330": a number, optionally followed by a unit or by "x" and another number.
    private static func isQuantity(_ word: String) -> Bool {
        let rest = word.drop { $0.isNumber }
        guard rest.count < word.count else { return false }
        if rest.isEmpty || units.contains(String(rest)) { return true }
        return rest.first == "x" && rest.dropFirst().allSatisfy { $0.isNumber }
    }
}
