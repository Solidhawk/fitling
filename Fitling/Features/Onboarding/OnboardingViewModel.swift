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
    var birthDay: Day
    var sex: Sex?
    var body: BodyInput
    var activityLevel: ActivityLevel?
    var goal: Goal?

    private let userID: UUID
    private let context: ModelContext
    private let timeZone: TimeZone
    private let now: () -> Date

    init(userID: UUID, context: ModelContext, locale: Locale, timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init) {
        self.userID = userID
        self.context = context
        self.timeZone = timeZone
        self.now = now
        body = BodyInput(locale: locale)
        // Thirty years back from the user's own today, which is also the age the picker opens on.
        birthDay = BirthDayPicking.day(30, yearsBefore: Day(now(), timeZone: timeZone))
    }

    /// Today where the user is.
    var today: Day {
        Day(now(), timeZone: timeZone)
    }

    var usesMetric: Bool {
        body.usesMetric
    }

    var isUnderage: Bool {
        !isAdult(bornOn: birthDay, on: today)
    }

    var canContinue: Bool {
        canContinue(at: step)
    }

    func canContinue(at step: Step) -> Bool {
        switch step {
        case .consent: consentGiven
        case .birthDate: isValidBirthDay(birthDay, on: today)
        case .sex: sex != nil
        case .height: body.heightCm.map { Limits.heightCm.contains($0) } ?? false
        case .weight: body.weightKg.map { Limits.weightKg.contains($0) } ?? false
        case .activity: activityLevel != nil
        case .goal: goal != nil
        case .result: plan != nil
        }
    }

    var bodyProfile: BodyProfile? {
        guard let sex, let activityLevel, let goal, body.isValid,
              let heightCm = body.heightCm, let weightKg = body.weightKg,
              isValidBirthDay(birthDay, on: today) else { return nil }
        return BodyProfile(birthDay: birthDay, sex: sex, heightCm: heightCm, weightKg: weightKg, activityLevel: activityLevel, goal: goal)
    }

    var plan: EnergyPlan? {
        bodyProfile.map { NutritionEngine.plan(for: $0, on: today) }
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

    /// Stores the profile and the first target period, which starts today.
    func finish() throws -> UserProfile {
        guard consentGiven, let bodyProfile, let plan else { throw FinishError.incomplete }
        let moment = now()
        let profile = UserProfile(
            id: userID,
            healthConsentAt: moment,
            healthConsentVersion: HealthConsent.currentVersion,
            body: bodyProfile,
            targets: plan.targets,
            targetsAreManual: false,
            updatedAt: moment
        )
        context.insert(profile)
        context.recordTargets(plan.targets, for: userID, from: today, at: moment)
        try context.save()
        return profile
    }
}
