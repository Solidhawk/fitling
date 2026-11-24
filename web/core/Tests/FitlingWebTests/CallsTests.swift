import Foundation
import Testing
import FitlingCore
@testable import FitlingWeb

/// The bridge answers with what FitlingCore answers in the app.
@Suite struct CallsTests {
    struct Targets: Decodable, Equatable {
        let kcal: Int
        let proteinG: Int
        let carbsG: Int
        let fatG: Int
    }

    struct Plan: Decodable {
        let bmr: Double
        let tdee: Double
        let targets: Targets
        let floorApplied: Bool
        let warnings: [String]
    }

    struct Failure: Decodable {
        let error: String
    }

    let maintainRequest = #"{"fn":"dailyPlan","input":{"birthDay":"1996-01-10","sex":"male","heightCm":180,"weightKg":80,"activityLevel":"moderate","goal":"maintain","today":"2026-11-18"}}"#

    /// The same profile and values as NutritionEngineTests.maintenanceTargetEqualsTotalExpenditure.
    @Test func dailyPlanMatchesTheApp() throws {
        let plan = try JSONDecoder().decode(Plan.self, from: handle(Data(maintainRequest.utf8)))
        #expect(plan.targets == Targets(kcal: 2760, proteinG: 128, carbsG: 389, fatG: 77))
        #expect(abs(plan.bmr - 1780) < 0.0001)
        #expect(plan.floorApplied == false)
        #expect(plan.warnings.isEmpty)
    }

    /// An absurd number from a form is an error with a message, never a trap in WebAssembly.
    @Test func absurdNumbersAreAnError() throws {
        let request = maintainRequest.replacingOccurrences(of: #""weightKg":80"#, with: #""weightKg":1e300"#)
        let failure = try JSONDecoder().decode(Failure.self, from: handle(Data(request.utf8)))
        #expect(failure.error.contains("weightKg"))
    }

    @Test func unknownFunctionIsAnError() throws {
        let failure = try JSONDecoder().decode(Failure.self, from: handle(Data(#"{"fn":"nope","input":{}}"#.utf8)))
        #expect(failure.error == "unknown function nope")
    }

    @Test func brokenJSONIsAnError() throws {
        let failure = try JSONDecoder().decode(Failure.self, from: handle(Data("{".utf8)))
        #expect(!failure.error.isEmpty)
    }

    // MARK: - The calls of onboarding, partner setup and Dagdoel (web fase 1)

    func answer(_ fn: String, _ input: String) throws -> [String: Any] {
        let data = handle(Data(#"{"fn":"\#(fn)","input":\#(input)}"#.utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    /// 5 ft 11 in and 176 lb, as the profile editor converts them.
    @Test func bodyInputConvertsImperialUnits() throws {
        let result = try answer("bodyInput", #"{"usesMetric":false,"fields":{"feet":5,"inches":11,"weight":176}}"#)
        #expect(number(result["heightCm"]) == 180.3)
        #expect(number(result["weightKg"]) == 79.8)
        #expect(result["isValid"] as? Bool == true)
        let short = try answer("bodyInput", #"{"usesMetric":true,"fields":{"centimetres":90}}"#)
        #expect(short["heightValid"] as? Bool == false)
        #expect(short["weightValid"] as? Bool == false)
    }

    /// Fields filled from a stored profile give back the stored values, not a rounded conversion.
    @Test func bodyInputKeepsStoredValues() throws {
        let result = try answer("bodyInput", #"{"usesMetric":false,"stored":{"heightCm":180,"weightKg":80}}"#)
        let fields = try #require(result["fields"] as? [String: Any])
        #expect(number(fields["feet"]) == 5)
        #expect(number(fields["inches"]) == 10.9)
        #expect(number(fields["weight"]) == 176.4)
        #expect(number(result["heightCm"]) == 180)
        #expect(number(result["weightKg"]) == 80)
    }

    @Test func birthDayChecksAgeAndAdulthood() throws {
        let adult = try answer("birthDay", #"{"birthDay":"1996-01-10","today":"2026-11-18"}"#)
        #expect(number(adult["age"]) == 30)
        #expect(adult["isAdult"] as? Bool == true)
        #expect(adult["isValid"] as? Bool == true)
        let young = try answer("birthDay", #"{"birthDay":"2010-01-01","today":"2026-11-18"}"#)
        #expect(young["isAdult"] as? Bool == false)
        #expect(young["isValid"] as? Bool == false)
    }

    @Test func macrosAndSharesMatchTheApp() throws {
        let targets = try answer("macros", #"{"kcal":2760,"weightKg":80,"goal":"maintain"}"#)
        #expect(number(targets["proteinG"]) == 128)
        #expect(number(targets["carbsG"]) == 389)
        #expect(number(targets["fatG"]) == 77)
        let shares = try answer("kcalShares", #"{"kcal":2760,"proteinG":128,"carbsG":389,"fatG":77}"#)
        #expect(abs((number(shares["protein"]) ?? 0) - 512.0 / 2760) < 0.0001)
        let warnings = try answer("warnings", #"{"kcal":2760,"bmr":1780,"tdee":2759,"sex":"male"}"#)
        #expect((warnings["warnings"] as? [String]) == [])
        let low = try answer("warnings", #"{"kcal":1000,"bmr":1780,"tdee":2759,"sex":"male"}"#)
        #expect(((low["warnings"] as? [String]) ?? []).contains("below_common_minimum"))
    }

    /// The same rule as TargetPeriodsTests: the newest period on the same day holds.
    @Test func targetsOnDayFollowTheNewestPeriod() throws {
        let result = try answer("targetsOnDay", #"{"day":"2026-11-10","fallback":{"kcal":2000,"proteinG":100,"carbsG":250,"fatG":70},"periods":[{"effectiveOn":"2026-11-10","updatedAtMs":1000,"targets":{"kcal":2200,"proteinG":120,"carbsG":270,"fatG":75}},{"effectiveOn":"2026-11-10","updatedAtMs":2000,"targets":{"kcal":2500,"proteinG":150,"carbsG":300,"fatG":80}}]}"#)
        #expect(number(result["kcal"]) == 2500)
    }

    @Test func aNewPartnerStartsAsTheAppSays() throws {
        let result = try answer("creature", #"{"level":1}"#)
        #expect(number(result["startShape"]) == 0.3)
        #expect(number(result["colorCount"]) == 3)
        #expect(number(result["growthStage"]) == 0)
    }

    @Test func goalFactorsAreTheRulesOwn() throws {
        let factors = try answer("goalFactors", "{}")
        #expect(number(factors["lose"]) == 0.8)
        #expect(number(factors["build_muscle"]) == 1.1)
        #expect(number(factors["maintain"]) == 1.0)
        #expect(number(factors["recomp"]) == 0.95)
    }

    /// What Dagdoel shows of how the target is built, and the ranges a typed target may take.
    @Test func profileRulesAreTheRulesOwn() throws {
        let rules = try answer("profileRules", "{}")
        let activity = try #require(rules["activityFactors"] as? [String: Any])
        #expect(number(activity["sedentary"]) == 1.2)
        #expect(number(activity["moderate"]) == 1.55)
        #expect(number(activity["very_active"]) == 1.9)
        let protein = try #require(rules["proteinPerKg"] as? [String: Any])
        #expect(number(protein["maintain"]) == 1.6)
        #expect(number(protein["recomp"]) == 2.2)
        let limits = try #require(rules["targetLimits"] as? [String: Any])
        #expect((limits["kcal"] as? [Any])?.compactMap(number) == [1, 20000])
        #expect((limits["proteinG"] as? [Any])?.compactMap(number) == [0, 1000])
        #expect((limits["carbsG"] as? [Any])?.compactMap(number) == [0, 5000])
        #expect((limits["fatG"] as? [Any])?.compactMap(number) == [0, 2000])
    }

    // Web phase 2: the rules for Vandaag and logging.
    @Test func searchKeyAndBarcodeAreTheCoresOwn() throws {
        #expect(try answer("searchKey", #"{"text":"  Crème Brûlée "}"#)["key"] as? String == "creme brulee")
        #expect(try answer("barcode", #"{"text":"036000291452"}"#)["gtin"] as? String == "0036000291452")
        #expect(try answer("barcode", #"{"text":"8712100849085"}"#)["gtin"] == nil)
    }

    @Test func recentProductsAreEachOnceNewestFirstInLowerCase() throws {
        let a = "8C1F0A52-5D0E-4C2B-9A51-6F2F7F5D2A10"
        let b = "0B5A1C2D-3E4F-4A5B-8C6D-7E8F9A0B1C2D"
        let result = try answer("recentProducts", #"{"logged":[{"productID":"\#(a)","updatedAtMs":1000},{"productID":"\#(b)","updatedAtMs":2000},{"productID":"\#(a)","updatedAtMs":3000}]}"#)
        #expect(result["ids"] as? [String] == [a.lowercased(), b.lowercased()])
        #expect(number(result["limit"]) == 20)
    }

    @Test func aPortionStartsAtOneServingAndAsksForMissingKcal() throws {
        let serving = try answer("portion", #"{"quantityUnit":"g","servingSize":30,"per100":{"kcal":400,"proteinG":10}}"#)
        #expect(serving["units"] as? [String] == ["serving", "g"])
        #expect(serving["defaultUnit"] as? String == "serving")
        #expect(number((serving["preview"] as? [String: Any])?["kcal"]) == 120)
        #expect(serving["canSave"] as? Bool == true)
        let noKcal = try answer("portion", #"{"quantityUnit":"g","per100":{"proteinG":10},"quantity":50,"unit":"g","kcalOnPackage":950}"#)
        #expect(noKcal["needsKcal"] as? Bool == true)
        #expect(noKcal["canSave"] as? Bool == false)
    }

    @Test func anEntryStoresWhatFoodDiaryStores() throws {
        let entry = try answer("logEntry", #"{"name":"Volkorenbrood","quantity":35.04,"unit":"g","per100":{"kcal":250,"proteinG":10}}"#)
        #expect(entry["name"] as? String == "Volkorenbrood")
        #expect(number(entry["quantity"]) == 35)
        #expect(number((entry["nutrients"] as? [String: Any])?["kcal"]) == 87.6)
        let data = handle(Data(#"{"fn":"logEntry","input":{"name":"x","quantity":2,"unit":"serving","per100":{"kcal":250}}}"#.utf8))
        #expect(String(decoding: data, as: UTF8.self) == "null")
    }

    @Test func anOwnProductIsCheckedAndRounded() throws {
        let fields = try answer("ownProduct", #"{"name":" Oma's appeltaart ","brand":"Bakkerij Jansen","gtin":"","isMillilitre":false,"kcal":280.44,"protein":3.2,"carbs":38,"servingSize":120}"#)["fields"] as? [String: Any]
        #expect(fields?["name"] as? String == "Oma's appeltaart")
        #expect(number(fields?["kcal100"]) == 280.4)
        #expect(fields?["searchName"] as? String == "oma's appeltaart bakkerij jansen")
        let refused = try answer("ownProduct", #"{"name":"x","brand":"","gtin":"","isMillilitre":false,"kcal":950}"#)
        #expect(refused["fields"] == nil)
    }

    @Test func dayTotalsCountUnknownMacros() throws {
        let totals = try answer("dayTotals", #"{"entries":[{"kcal":100,"proteinG":5},{"kcal":50.5}]}"#)
        #expect(number(totals["kcal"]) == 150.5)
        #expect(number(totals["proteinG"]) == 5)
        #expect(number(totals["unknownProtein"]) == 1)
        #expect(number(totals["unknownFat"]) == 2)
    }

    /// Three days on target after creation: the same mood and energy as the engine gives the app.
    @Test func partnerSnapshotIsTheEnginesOwn() throws {
        let state = CreatureState(species: .owl, colorIndex: 0, tone: .sweet, createdOn: Day(isoString: "2026-11-14")!)
        let days = ["2026-11-21", "2026-11-22", "2026-11-23"]
        let records = days.map {
            DayRecord(day: Day(isoString: $0)!, kcal: 2000, kcalTarget: 2000, proteinG: 120, proteinTargetG: 120, entryCount: 1, workoutCompleted: false)
        }
        let expected = CreatureEngine.snapshot(of: state, records: records, today: Day(isoString: "2026-11-24")!)
        let entries = days.map { #"{"day":"\#($0)","kcal":2000,"proteinG":120}"# }.joined(separator: ",")
        let creature = #"{"species":"owl","colorIndex":0,"tone":"sweet","createdOn":"2026-11-14","bodyShape":0.3,"xp":0,"offTargetDays":0}"#
        let fallback = #"{"kcal":2000,"proteinG":120,"carbsG":250,"fatG":70}"#
        let result = try answer(
            "partnerSnapshot",
            #"{"creature":\#(creature),"entries":[\#(entries)],"workoutDays":[],"periods":[],"fallback":\#(fallback),"today":"2026-11-24"}"#
        )
        #expect(result["mood"] as? String == expected.mood.rawValue)
        #expect(number(result["energy"]) == expected.energy)
        #expect(number(result["level"]) == Double(expected.level))
        #expect(number(result["historyDays"]) == 8)
    }

    @Test func aNameFollowsTheBrowsersLanguagesThenEnglishThenDutch() throws {
        #expect(try answer("localizedText", #"{"values":{"nl":"Brood","en":"Bread"},"languages":["de-DE","en-US"]}"#)["text"] as? String == "Bread")
        #expect(try answer("localizedText", #"{"values":{"nl":"Brood"},"languages":["de"]}"#)["text"] as? String == "Brood")
    }

    // Web phase 3: the partner as the engine folds and dresses it.
    func partnerDays(xp: Int, lastProcessed: String?, entries: [String], today: String) -> String {
        let row = lastProcessed.map { #","lastProcessedDay":"\#($0)""# } ?? ""
        let creature = #"{"species":"owl","colorIndex":0,"tone":"sweet","createdOn":"2026-11-14","bodyShape":0.3,"xp":\#(xp),"offTargetDays":0\#(row)}"#
        let logged = entries.map { #"{"day":"\#($0)","kcal":2000,"proteinG":130}"# }.joined(separator: ",")
        let fallback = #"{"kcal":2000,"proteinG":120,"carbsG":250,"fatG":70}"#
        return #"{"creature":\#(creature),"entries":[\#(logged)],"workoutDays":[],"periods":[],"fallback":\#(fallback),"today":"\#(today)"}"#
    }

    func records(_ days: [String]) -> [DayRecord] {
        days.map { DayRecord(day: Day(isoString: $0)!, kcal: 2000, kcalTarget: 2000, proteinG: 130, proteinTargetG: 120, entryCount: 1, workoutCompleted: false) }
    }

    @Test func partnerAdvanceIsTheEnginesOwn() throws {
        let days = ["2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23"]
        let state = CreatureState(species: .owl, colorIndex: 0, tone: .sweet, createdOn: Day(isoString: "2026-11-14")!, xp: 80)
        let expected = CreatureEngine.advance(state, records: records(days), today: Day(isoString: "2026-11-24")!)
        let result = try answer("partnerAdvance", partnerDays(xp: 80, lastProcessed: nil, entries: days, today: "2026-11-24"))
        let creature = try #require(result["creature"] as? [String: Any])
        #expect(number(creature["xp"]) == Double(expected.state.xp))
        #expect(creature["lastProcessedDay"] as? String == expected.state.lastProcessedDay?.isoString)
        #expect(result["changed"] as? Bool == (expected.state != state))
        #expect((result["events"] as? [[String: Any]])?.count == expected.events.count)
        #expect(try answer("advanceFrom", #"{"creature":{"species":"owl","colorIndex":0,"tone":"sweet","createdOn":"2026-11-14","bodyShape":0.3,"xp":0,"offTargetDays":0,"lastProcessedDay":"2026-11-20"}}"#)["firstDay"] as? String == "2026-11-14")
    }

    @Test func advancingTheSameDaysAgainChangesNothing() throws {
        let days = ["2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23"]
        let once = try answer("partnerAdvance", partnerDays(xp: 80, lastProcessed: nil, entries: days, today: "2026-11-24"))
        let creature = try #require(once["creature"] as? [String: Any])
        let twice = try answer(
            "partnerAdvance",
            partnerDays(xp: Int(number(creature["xp"]) ?? 0), lastProcessed: creature["lastProcessedDay"] as? String, entries: days, today: "2026-11-24")
        )
        #expect(twice["changed"] as? Bool == false)
        #expect((twice["events"] as? [Any])?.isEmpty == true)
    }

    @Test func todayXPIsTheEnginesOwn() throws {
        let expected = CreatureEngine.xp(for: records(["2026-11-24"])[0])
        let result = try answer("partnerSnapshot", partnerDays(xp: 0, lastProcessed: nil, entries: ["2026-11-24"], today: "2026-11-24"))
        let today = try #require(result["todayXP"] as? [String: Any])
        #expect(number(today["logging"]) == Double(expected.logging))
        #expect(number(today["withinTarget"]) == Double(expected.withinTarget))
        #expect(number(today["protein"]) == Double(expected.protein))
        #expect(result["lockedColorLevels"] as? [Int] == CreatureEngine.colorUnlockLevels)
        let items = try #require(result["items"] as? [[String: Any]])
        #expect(items.map { $0["item"] as? String } == CreatureItem.allCases.map(\.rawValue))
        #expect(items.map { number($0["unlockLevel"]) } == CreatureItem.allCases.map { Double($0.unlockLevel) })
    }

    @Test func wearingFollowsTheCore() throws {
        let worn = try answer("wearing", #"{"worn":["scarf","crown"],"item":"cap","unlocked":["scarf","cap","bow","glasses","backpack","crown"]}"#)
        #expect(worn["worn"] as? [String] == ["scarf", "cap"])
        let locked = try answer("wearing", #"{"worn":[],"item":"crown","unlocked":["scarf"]}"#)
        #expect(locked["worn"] as? [String] == [])
    }

    // Web phase 4: training, from the same TrainingRecords as TrainingStore.
    struct TrainingJSON: Encodable {
        var userID = UUID()
        var today = "2026-11-18"
        var languages = ["nl"]
        var exercises: [ExerciseRecord] = []
        var programs: [ProgramRecord] = []
        var days: [ProgramDayRecord] = []
        var items: [ProgramItemRecord] = []
        var settings: [ExerciseSettingRecord] = []
        var sessions: [SessionRecord] = []
        var sets: [SetRecord] = []

        func with(_ extra: String) throws -> String {
            let training = String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
            return extra.isEmpty ? #"{"training":\#(training)}"# : #"{"training":\#(training),\#(extra)}"#
        }
    }

    /// A shared squat programme of two days (3 × 6–8) and a finished workout on the first day three days ago.
    func squatProgramme() -> (TrainingJSON, ExerciseRecord, [ProgramDayRecord]) {
        let squat = ExerciseRecord(
            id: UUID(), ownerID: nil, name: LocalizedText(["nl": "Squat"]), kind: "compound", loadType: "external",
            primaryMuscles: ["quads"], secondaryMuscles: [], defaultStepKg: 2.5
        )
        let program = ProgramRecord(id: UUID(), ownerID: nil, name: LocalizedText(["nl": "Volledig lichaam"]), daysPerWeek: 2)
        let days = (0..<2).map {
            ProgramDayRecord(id: UUID(), programID: program.id, ownerID: nil, name: LocalizedText(["nl": "Dag \($0 + 1)"]), position: $0, updatedAt: 0)
        }
        let items = days.map {
            ProgramItemRecord(id: UUID(), programDayID: $0.id, ownerID: nil, exerciseID: squat.id, position: 0, targetSets: 3, repMin: 6, repMax: 8, restSeconds: 150)
        }
        let session = SessionRecord(id: UUID(), programDayID: days[0].id, performedOn: Day(isoString: "2026-11-15")!, startedAt: 1_794_740_000, endedAt: 1_794_743_600)
        let sets = (0..<3).map { SetRecord(id: UUID(), sessionID: session.id, exerciseID: squat.id, position: $0, weightKg: 100, reps: 6, rpe: 7) }
        let json = TrainingJSON(exercises: [squat], programs: [program], days: days, items: items, sessions: [session], sets: sets)
        return (json, squat, days)
    }

    @Test func trainingOverviewIsTheStoresOwn() throws {
        let (json, _, days) = squatProgramme()
        let result = try answer("trainingOverview", try json.with(""))
        let next = try #require(result["next"] as? [String: Any])
        #expect(next["kind"] as? String == "programDay")
        #expect(next["dayID"] as? String == days[1].id.uuidString.lowercased())
        #expect(next["dayName"] as? String == "Dag 2")
        let recent = try #require(result["recent"] as? [[String: Any]])
        #expect(recent.first?["title"] as? String == "Dag 1")
        #expect(number(recent.first?["setCount"]) == 3)
        #expect((result["programs"] as? [[String: Any]])?.first?["shared"] as? Bool == true)
    }

    @Test func workoutPrefillsFromTheAdvice() throws {
        var (json, squat, days) = squatProgramme()
        let today = SessionRecord(id: UUID(), programDayID: days[1].id, performedOn: Day(isoString: "2026-11-18")!, startedAt: 1_795_000_000)
        json.sessions.append(today)
        let result = try answer("workout", try json.with(#""sessionID":"\#(today.id)","added":[],"usesPounds":false"#))
        let entry = try #require((result["entries"] as? [[String: Any]])?.first)
        #expect(entry["exerciseID"] as? String == squat.id.uuidString.lowercased())
        #expect((entry["advice"] as? [String: Any])?["kind"] as? String == "keepGoing")
        let draft = try #require(entry["draft"] as? [String: Any])
        #expect(number(draft["weight"]) == 100 && number(draft["reps"]) == 7)
        #expect(number(entry["restSeconds"]) == 150)
        let pounds = try answer("workout", try json.with(#""sessionID":"\#(today.id)","added":[],"usesPounds":true"#))
        let poundsDraft = try #require(((pounds["entries"] as? [[String: Any]])?.first)?["draft"] as? [String: Any])
        #expect(number(poundsDraft["weight"]) == 220.46)
    }

    @Test func loggedSetIsBounded() throws {
        let pounds = try answer("loggedSet", #"{"weight":135,"reps":5,"usesPounds":true}"#)
        #expect(number(pounds["weightKg"]) == 61.23 && pounds["canLog"] as? Bool == true)
        let missing = try answer("loggedSet", #"{"weight":60,"usesPounds":false}"#)
        #expect(missing["canLog"] as? Bool == false)
    }

    @Test func exerciseProgressListsEveryWorkout() throws {
        var (json, squat, _) = squatProgramme()
        let later = SessionRecord(id: UUID(), programDayID: nil, performedOn: Day(isoString: "2026-11-17")!, startedAt: 1_794_900_000, endedAt: 1_794_903_600)
        json.sessions.append(later)
        json.sets.append(SetRecord(id: UUID(), sessionID: later.id, exerciseID: squat.id, position: 0, weightKg: 105, reps: 5, rpe: 8))
        let result = try answer("exerciseProgress", try json.with(#""exerciseID":"\#(squat.id)""#))
        #expect(number(result["workouts"]) == 2)
        #expect((result["points"] as? [[String: Any]])?.count == 2)
        #expect(number(result["heaviestKg"]) == 105)
        #expect(number(result["stepKg"]) == 2.5)
    }

    @Test func measurementsFollowTheCore() throws {
        #expect(number(try answer("measurementStored", #"{"value":176,"kind":"weight","usesMetric":false}"#)["value"]) == 79.8)
        #expect(try answer("measurementStored", #"{"value":600,"kind":"waist","usesMetric":true}"#)["value"] == nil)
    }
}
