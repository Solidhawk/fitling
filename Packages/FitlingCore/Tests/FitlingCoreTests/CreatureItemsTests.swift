import Testing
@testable import FitlingCore

/// What the partner wears, shared by the app and the web (web phase 3); PartnerTests in the app.
@Suite struct CreatureItemsTests {
    @Test func lockedItemsCannotBeWorn() {
        #expect(CreatureEngine.wearing([], toggling: .scarf, unlocked: []) == [])
    }

    @Test func wearingACapTakesOffTheCrown() {
        let all = CreatureItem.allCases
        var worn = CreatureEngine.wearing([], toggling: .crown, unlocked: all)
        worn = CreatureEngine.wearing(worn, toggling: .scarf, unlocked: all)
        #expect(worn == [.scarf, .crown])
        worn = CreatureEngine.wearing(worn, toggling: .cap, unlocked: all)
        #expect(worn == [.scarf, .cap])
        worn = CreatureEngine.wearing(worn, toggling: .scarf, unlocked: all)
        #expect(worn == [.cap])
        #expect(CreatureItem.cap.blocked == .crown)
        #expect(CreatureItem.scarf.blocked == nil)
    }

    @Test func itemsAreKeptInTheirOwnOrder() {
        let all = CreatureItem.allCases
        let worn = CreatureEngine.wearing([.crown, .backpack], toggling: .scarf, unlocked: all)
        #expect(worn == all.filter { [.crown, .backpack, .scarf].contains($0) })
    }
}
