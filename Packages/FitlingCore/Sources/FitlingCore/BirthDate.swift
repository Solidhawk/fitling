import Foundation

// Works on days, not on `Date`: a birthday is a calendar day, and a `Date` would move it when
// the device changes time zone. A 29 February birthday is reached on 1 March in other years.
public func age(bornOn birthDay: Day, on day: Day) -> Int {
    let born = birthDay.components
    let now = day.components
    let hadBirthday = (now.month, now.day) >= (born.month, born.day)
    return now.year - born.year - (hadBirthday ? 0 : 1)
}

public func isAdult(bornOn birthDay: Day, on day: Day) -> Bool {
    age(bornOn: birthDay, on: day) >= Limits.minimumAge
}

/// Adult and not before `Limits.earliestBirthDay`: the same rule as the `birth_date` check in Postgres,
/// so a profile the app accepts can always be pushed.
public func isValidBirthDay(_ birthDay: Day, on day: Day) -> Bool {
    birthDay >= Limits.earliestBirthDay && isAdult(bornOn: birthDay, on: day)
}
