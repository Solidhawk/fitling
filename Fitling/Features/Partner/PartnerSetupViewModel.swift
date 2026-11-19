import Foundation
import Observation
import SwiftData
import FitlingCore

/// Choosing a partner: species, name, colour and the voice of its reminders. Asked once, right
/// after onboarding or at the first start of a version that has partners.
@Observable
@MainActor
final class PartnerSetupViewModel {
    /// The check on `creatures.name`. Postgres counts code points, so a name is limited by its
    /// Unicode scalars: an emoji made of five scalars takes five of the 24.
    static let nameLimit = 24

    private(set) var species: Species?
    var name = ""
    var colorIndex = 0
    var tone: MessageTone = .sweet

    private let userID: UUID
    private let context: ModelContext
    private let timeZone: TimeZone
    private let now: () -> Date
    /// The species name that was filled in for the user, so choosing another species replaces it
    /// but never a name the user typed.
    private var suggestedName: String?

    init(userID: UUID, context: ModelContext, timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init) {
        self.userID = userID
        self.context = context
        self.timeZone = timeZone
        self.now = now
    }

    /// The colours to choose from now; more unlock at higher levels.
    var colorCount: Int {
        CreatureEngine.baseColorCount
    }

    var cleanedName: String {
        Self.limited(name.trimmingCharacters(in: .whitespacesAndNewlines)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool {
        species != nil && !cleanedName.isEmpty
    }

    /// `defaultName` is the species' own name in the user's language, filled in until the user types one.
    func choose(_ species: Species, defaultName: String) {
        self.species = species
        if name.isEmpty || name == suggestedName {
            name = defaultName
            suggestedName = defaultName
        }
    }

    /// While typing: cut off at the limit, keep spaces, so "Mr Pip" can be typed.
    static func limited(_ name: String) -> String {
        var result = ""
        var scalars = 0
        for character in name {
            scalars += character.unicodeScalars.count
            guard scalars <= nameLimit else { break }
            result.append(character)
        }
        return result
    }

    /// Stores the partner. When a partner already exists for this user (another device made one
    /// meanwhile), that one is kept.
    @discardableResult
    func save() -> Creature? {
        guard let species, canSave else { return nil }
        if let existing = context.creature(of: userID) { return existing }
        let state = CreatureState(
            species: species, colorIndex: min(max(colorIndex, 0), colorCount - 1), tone: tone,
            createdOn: Day(now(), timeZone: timeZone)
        )
        let creature = Creature(userID: userID, name: cleanedName, state: state, updatedAt: now())
        context.insert(creature)
        try? context.save()
        return creature
    }
}
