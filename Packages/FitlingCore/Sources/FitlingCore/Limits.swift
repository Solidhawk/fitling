import Foundation

// Must stay identical to the `check` constraints on `public.profiles`; a value the app accepts
// but the database rejects would leave a profile that can never be pushed.
public enum Limits {
    public static let heightCm: ClosedRange<Double> = 100...250
    public static let weightKg: ClosedRange<Double> = 30...350
    public static let minimumAge = 18
    /// 1900-01-01.
    public static let earliestBirthDay = Day(ordinal: -25567)
    public static let kcal: ClosedRange<Int> = 1...20000
    public static let proteinG: ClosedRange<Int> = 0...1000
    public static let carbsG: ClosedRange<Int> = 0...5000
    public static let fatG: ClosedRange<Int> = 0...2000
    /// `food_entries.quantity`: more than 0 and at most 10 000 (grams, millilitres or servings).
    public static let foodQuantity: ClosedRange<Double> = 0.1...10000
    /// `products.kcal_100`.
    public static let kcalPer100: ClosedRange<Double> = 0...900
}
