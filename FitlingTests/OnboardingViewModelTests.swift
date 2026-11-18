import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

@MainActor
@Suite struct OnboardingViewModelTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let today = BirthDateCalendar.date(from: "2026-11-18")!.addingTimeInterval(12 * 3600)

    init() throws {
        container = try makeModelContainer(inMemory: true)
    }

    func makeViewModel(locale: Locale = Locale(identifier: "nl_NL")) -> OnboardingViewModel {
        let today = today
        return OnboardingViewModel(userID: UUID(), context: context, locale: locale, now: { today })
    }

    /// Fills every step with valid answers and walks forward until `step`.
    func advance(_ viewModel: OnboardingViewModel, to step: OnboardingViewModel.Step) {
        viewModel.consentGiven = true
        viewModel.birthDate = BirthDateCalendar.date(from: "1996-01-10")!
        viewModel.sex = .male
        viewModel.heightInput = Measurement(value: 180, unit: .centimeters)
        viewModel.weightInput = Measurement(value: 80, unit: .kilograms)
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

    @Test func underageBlocksAndFlags() {
        let viewModel = makeViewModel()
        advance(viewModel, to: .birthDate)
        viewModel.birthDate = BirthDateCalendar.date(from: "2009-01-01")!
        #expect(viewModel.isUnderage)
        #expect(viewModel.canContinue == false)
        viewModel.next()
        #expect(viewModel.step == .birthDate)
    }

    @Test func exactlyEighteenPasses() {
        let viewModel = makeViewModel()
        advance(viewModel, to: .birthDate)
        viewModel.birthDate = BirthDateCalendar.date(from: "2008-11-18")!
        #expect(viewModel.isUnderage == false)
        #expect(viewModel.canContinue)
    }

    @Test func imperialInputStoredMetric() throws {
        let viewModel = makeViewModel(locale: Locale(identifier: "en_US"))
        #expect(viewModel.usesMetric == false)
        advance(viewModel, to: .result)
        viewModel.weightInput = Measurement(value: 176, unit: .pounds)
        viewModel.heightInput = Measurement(value: 70, unit: .inches)
        let profile = try viewModel.finish()
        #expect(abs(profile.weightKg - 79.8) < 0.05)
        #expect(abs(profile.heightCm - 177.8) < 0.05)
    }

    @Test func outOfRangeWeightBlocks() {
        let viewModel = makeViewModel()
        advance(viewModel, to: .weight)
        viewModel.weightInput = Measurement(value: 20, unit: .kilograms)
        #expect(viewModel.canContinue == false)
        viewModel.weightInput = nil
        #expect(viewModel.canContinue == false)
    }

    @Test func finishStoresConsentAndTargets() throws {
        let viewModel = makeViewModel()
        advance(viewModel, to: .result)
        #expect(viewModel.calculation?.targets == NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77))
        let profile = try viewModel.finish()
        #expect(profile.targets == NutritionTargets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77))
        #expect(profile.healthConsentVersion == HealthConsent.currentVersion)
        #expect(profile.healthConsentAt == today)
        #expect(profile.needsPush)
        #expect(BirthDateCalendar.string(from: profile.birthDate) == "1996-01-10")
        #expect(try context.fetch(FetchDescriptor<UserProfile>()).count == 1)
    }

    @Test func backReturnsToPreviousStep() {
        let viewModel = makeViewModel()
        advance(viewModel, to: .sex)
        viewModel.back()
        #expect(viewModel.step == .birthDate)
    }
}
