import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

@MainActor
@Suite struct OnboardingViewModelTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let userID = UUID()
    /// 2026-11-18, 11:06 UTC.
    let now = Date(timeIntervalSince1970: 1_795_000_000)

    init() throws {
        container = try makeModelContainer(inMemory: true)
    }

    func makeViewModel(locale: Locale = Locale(identifier: "nl_NL"), timeZone: TimeZone = .gmt, now: Date? = nil) -> OnboardingViewModel {
        let moment = now ?? self.now
        return OnboardingViewModel(userID: userID, context: context, locale: locale, timeZone: timeZone, now: { moment })
    }

    /// Fills every step with valid answers and walks forward until `step`.
    func advance(_ viewModel: OnboardingViewModel, to step: OnboardingViewModel.Step) {
        viewModel.consentGiven = true
        viewModel.birthDay = Day(year: 1996, month: 1, day: 10)!
        viewModel.sex = .male
        viewModel.body = BodyInput(usesMetric: viewModel.usesMetric, heightCm: 180, weightKg: 80)
        viewModel.activityLevel = .moderate
        viewModel.goal = .maintain
        while viewModel.step != step {
            viewModel.next()
        }
    }

    @Test func cannotPassConsentWithoutAgreeing() {
        let viewModel = makeViewModel()
        #expect(viewModel.canContinue == false)
        viewModel.next()
        #expect(viewModel.step == .consent)
        viewModel.consentGiven = true
        viewModel.next()
        #expect(viewModel.step == .birthDate)
    }

    @Test func defaultBirthDayIsThirtyYearsAgoInAnyTimeZone() throws {
        // 2026-11-19 03:00 UTC is still the evening of the 18th in Los Angeles.
        let moment = Date(timeIntervalSince1970: 1_795_057_200)
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(makeViewModel(timeZone: losAngeles, now: moment).birthDay == Day(year: 1996, month: 11, day: 18))
        #expect(makeViewModel(timeZone: .gmt, now: moment).birthDay == Day(year: 1996, month: 11, day: 19))
    }

    @Test func underageBlocksAndFlags() {
        let viewModel = makeViewModel()
        advance(viewModel, to: .birthDate)
        viewModel.birthDay = Day(year: 2009, month: 1, day: 1)!
        #expect(viewModel.isUnderage)
        #expect(viewModel.canContinue == false)
        viewModel.next()
        #expect(viewModel.step == .birthDate)
    }

    @Test func exactlyEighteenPasses() {
        let viewModel = makeViewModel()
        advance(viewModel, to: .birthDate)
        viewModel.birthDay = Day(year: 2008, month: 11, day: 18)!
        #expect(viewModel.isUnderage == false)
        #expect(viewModel.canContinue)
    }

    @Test func birthDayBefore1900Blocks() {
        let viewModel = makeViewModel()
        advance(viewModel, to: .birthDate)
        viewModel.birthDay = Day(year: 1899, month: 12, day: 31)!
        #expect(viewModel.canContinue == false)
        #expect(viewModel.bodyProfile == nil)
    }

    @Test func imperialHeightAndWeightGiveTheSameProfileAsMetric() throws {
        let metric = makeViewModel()
        advance(metric, to: .result)
        metric.body.centimetres = 177.8
        metric.body.weight = 79.8

        let imperial = makeViewModel(locale: Locale(identifier: "en_US"))
        #expect(imperial.usesMetric == false)
        advance(imperial, to: .result)
        imperial.body.feet = 5
        imperial.body.inches = 10
        imperial.body.weight = 176

        let profile = try #require(imperial.bodyProfile)
        #expect(profile == metric.bodyProfile)
        #expect(profile.heightCm == 177.8)
        #expect(profile.weightKg == 79.8)
    }

    @Test func outOfRangeWeightBlocks() {
        let viewModel = makeViewModel()
        advance(viewModel, to: .weight)
        viewModel.body.weight = 20
        #expect(viewModel.canContinue == false)
        viewModel.body.weight = nil
        #expect(viewModel.canContinue == false)
    }

    @Test func finishStoresTheProfileAndTheFirstTargetPeriod() throws {
        let viewModel = makeViewModel()
        advance(viewModel, to: .result)
        let targets = NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77)
        #expect(viewModel.plan?.targets == targets)

        let profile = try viewModel.finish()

        #expect(profile.targets == targets)
        #expect(profile.healthConsentVersion == HealthConsent.currentVersion)
        #expect(profile.healthConsentAt == now)
        #expect(profile.needsPush)
        #expect(profile.birthDate == "1996-01-10")
        #expect(try context.fetch(FetchDescriptor<UserProfile>()).count == 1)
        let period = try #require(try context.fetch(FetchDescriptor<TargetPeriod>()).first)
        #expect(period.userID == userID)
        #expect(period.effectiveOn == "2026-11-18")
        #expect(period.targets == targets)
        #expect(period.needsPush)
    }

    @Test func resultExplainsTheFloorWhenItWasApplied() throws {
        let viewModel = makeViewModel()
        advance(viewModel, to: .goal)
        viewModel.birthDay = Day(year: 1956, month: 1, day: 10)!
        viewModel.sex = .female
        viewModel.body = BodyInput(usesMetric: true, heightCm: 160, weightKg: 60)
        viewModel.activityLevel = .sedentary
        viewModel.goal = .lose

        let plan = try #require(viewModel.plan)
        #expect(plan.floorApplied)
        #expect(plan.targets.kcal == 1200)
    }

    @Test func returnToOnlyGoesBack() {
        let viewModel = makeViewModel()
        advance(viewModel, to: .sex)
        viewModel.returnTo(.goal)
        #expect(viewModel.step == .sex)
        viewModel.returnTo(.consent)
        #expect(viewModel.step == .consent)
    }

    @Test func canContinueIsPerStep() {
        let viewModel = makeViewModel()
        advance(viewModel, to: .sex)
        viewModel.sex = nil
        #expect(viewModel.canContinue(at: .consent))
        #expect(viewModel.canContinue(at: .sex) == false)
    }
}
