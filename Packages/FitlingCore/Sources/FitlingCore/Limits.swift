import Foundation

// Must stay identical to the `check` constraints on `public.profiles`; a value the app accepts
// but the database rejects would leave a profile that can never be pushed.
public enum Limits {
    public static let heightCm: ClosedRange<Double> = 100...250
    public static let weightKg: ClosedRange<Double> = 30...350
    public static let minimumAge = 18
    public static let earliestBirthDate = DateComponents(year: 1900, month: 1, day: 1)
    public static let kcal: ClosedRange<Int> = 1...20000
    public static let proteinG: ClosedRange<Int> = 0...1000
    public static let carbsG: ClosedRange<Int> = 0...5000
    public static let fatG: ClosedRange<Int> = 0...2000
}
