extension CreatureItem {
    /// The item that cannot be worn at the same time: both go on top of the head.
    public var blocked: CreatureItem? {
        switch self {
        case .cap: .crown
        case .crown: .cap
        default: nil
        }
    }
}

extension CreatureEngine {
    /// What the partner wears after putting `item` on or taking it off, shared by the app and the web. A locked item
    /// changes nothing (`worn` comes back as it was); a cap and a crown do not fit on one head, so putting one on takes
    /// the other off. Otherwise the result keeps the order of `CreatureItem.allCases`, so two devices that wear the
    /// same things store the same row.
    public static func wearing(_ worn: [CreatureItem], toggling item: CreatureItem, unlocked: [CreatureItem]) -> [CreatureItem] {
        guard unlocked.contains(item) else { return worn }
        var next = worn.filter { $0 != item }
        if !worn.contains(item) {
            next.removeAll { $0 == item.blocked }
            next.append(item)
        }
        return CreatureItem.allCases.filter(next.contains)
    }
}
