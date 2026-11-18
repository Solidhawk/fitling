import Foundation
import Observation
import SwiftData
import FitlingCore

enum HealthConsent {
    /// Raise when the consent text changes in substance; the profile records which version was accepted.
    static let currentVersion = 1
}

@Observable
@MainActor
final class OnboardingViewModel {
    enum Step: Int, CaseIterable {
        case consent, birthDate, sex, height, weight, activity, goal, result
    }

    private(set) var step: Step = .consent
    var consentGiven = false
    var birthDate: Date
    var sex: Sex?
    /// In the user's own unit; stored as centimetres.
    var heightInput: Measurement<UnitLength>?
    /// In the user's own unit; stored as kilograms.
    var weightInput: Measurement<UnitMass>?
    var activityLevel: ActivityLevel?
    var goal: Goal?
    let usesMetric: Bool

    private let userID: UUID
    private let context: ModelContext
    private let now: () -> Date

    init(userID: UUID, context: ModelContext, locale: Locale, now: @escaping () -> Date = Date.init) {
        self.userID = userID
        self.context = context
        self.now = now
        usesMetric = locale.measurementSystem == .metric
        let calendar = BirthDateCalendar.calendar
        birthDate = calendar.date(byAdding: .year, value: -30, to: calendar.startOfDay(for: now())) ?? now()
    }

    var heightCm: Double? {
        heightInput.map { ($0.converted(to: .centimeters).value * 10).rounded() / 10 }
    }

    var weightKg: Double? {
        weightInput.map { ($0.converted(to: .kilograms).value * 10).rounded() / 10 }
    }

    var isUnderage: Bool {
        !isAdult(birthDate: birthDate, on: now(), calendar: BirthDateCalendar.calendar)
    }

    /// The earliest date the birth-date picker offers; the database rejects anything before it.
    var earliestBirthDate: Date {
        BirthDateCalendar.calendar.date(from: Limits.earliestBirthDate) ?? .distantPast
    }

    var canContinue: Bool {
        canContinue(at: step)
    }

    func canContinue(at step: Step) -> Bool {
        switch step {
        case .consent: consentGiven
        case .birthDate: isValidBirthDate(birthDate, on: now(), calendar: BirthDateCalendar.calendar)
        case .sex: sex != nil
        case .height: heightCm.map { Limits.heightCm.contains($0) } ?? false
        case .weight: weightKg.map { Limits.weightKg.contains($0) } ?? false
        case .activity: activityLevel != nil
        case .goal: goal != nil
        case .result: calculation != nil
        }
    }

    var bodyProfile: BodyProfile? {
        guard let sex, let heightCm, let weightKg, let activityLevel, let goal,
              Limits.heightCm.contains(heightCm), Limits.weightKg.contains(weightKg),
              isValidBirthDate(birthDate, on: now(), calendar: BirthDateCalendar.calendar) else { return nil }
        return BodyProfile(
            birthDate: BirthDateCalendar.calendar.startOfDay(for: birthDate),
            sex: sex,
            heightCm: heightCm,
            weightKg: weightKg,
            activityLevel: activityLevel,
            goal: goal
        )
    }

    var calculation: EnergyCalculation? {
        bodyProfile.map { calculateEnergy(for: $0, on: now(), calendar: BirthDateCalendar.calendar) }
    }

    func next() {
        guard canContinue, let following = Step(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    /// Follows the navigation stack back (system back button or edge swipe); never jumps forward.
    func returnTo(_ earlier: Step) {
        if earlier.rawValue < step.rawValue { step = earlier }
    }

    enum FinishError: Error {
        case incomplete
    }

    func finish() throws -> UserProfile {
        guard consentGiven, let body = bodyProfile, let calculation else { throw FinishError.incomplete }
        let moment = now()
        let profile = UserProfile(
            id: userID,
            healthConsentAt: moment,
            healthConsentVersion: HealthConsent.currentVersion,
            body: body,
            targets: calculation.targets,
            targetsAreManual: false,
            updatedAt: moment
        )
        context.insert(profile)
        try context.save()
        return profile
    }
}
