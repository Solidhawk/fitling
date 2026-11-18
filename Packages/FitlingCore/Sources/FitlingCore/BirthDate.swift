import Foundation

// Compares (month, day) instead of using Calendar.dateComponents(.year): Foundation on Darwin
// and Linux disagree on anniversaries of 29 February. This way a 29 February birthday is
// reached on 1 March in non-leap years, on every platform.
public func age(birthDate: Date, on date: Date, calendar: Calendar) -> Int {
    let born = calendar.dateComponents([.year, .month, .day], from: birthDate)
    let now = calendar.dateComponents([.year, .month, .day], from: date)
    guard let bornYear = born.year, let bornMonth = born.month, let bornDay = born.day,
          let nowYear = now.year, let nowMonth = now.month, let nowDay = now.day else { return 0 }
    let hadBirthday = (nowMonth, nowDay) >= (bornMonth, bornDay)
    return nowYear - bornYear - (hadBirthday ? 0 : 1)
}

public func isAdult(birthDate: Date, on date: Date, calendar: Calendar) -> Bool {
    age(birthDate: birthDate, on: date, calendar: calendar) >= Limits.minimumAge
}

/// Adult and not before `Limits.earliestBirthDate`: the same rule as the `birth_date` check in Postgres,
/// so a profile the app accepts can always be pushed.
public func isValidBirthDate(_ birthDate: Date, on date: Date, calendar: Calendar) -> Bool {
    guard let earliest = calendar.date(from: Limits.earliestBirthDate) else { return false }
    return birthDate >= earliest && isAdult(birthDate: birthDate, on: date, calendar: calendar)
}
