# Fitling web fase 4: Training — implementatieplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** het tabblad Training van de iPhone 1 op 1 op het web: volgende training, coach, schema's (nieuw, kopiëren, aanpassen), samenstellen, een training loggen met rusttimer, advies en records, voortgang per oefening met grafiek en animatie, volume per spiergroep, lichaam en voortgangsfoto's.

**Architecture:** de leeslogica van `TrainingStore` en `WorkoutViewModel` (welke training is de volgende, de coach, de geschiedenis per oefening, de regels per oefening, het vooraf invullen, de begrenzing van een set) verhuist naar FitlingCore als één waarde `TrainingRecords` met alle rijen van de gebruiker en de gedeelde catalogus. iOS bouwt die waarde uit SwiftData en schrijft zelf; het web bouwt hem uit Supabase, vraagt de uitkomsten via de brug (`fitling_call`) en schrijft met supabase-js. Grafieken zijn eigen SVG, foto's blijven in IndexedDB op het apparaat.

**Tech Stack:** Swift 6 (FitlingCore, WASM-brug), React 18 + TypeScript, supabase-js, Vitest, Playwright (WebKit en Chrome).

**Spec:** `docs/superpowers/specs/2026-11-24-fitling-web-design.md` (fase 4).

## Global Constraints

- "Elke regel die op iOS en web hetzelfde moet uitkomen, staat in FitlingCore"; iOS roept daarna FitlingCore aan, met dezelfde uitkomst (de iOS-tests `TrainingTests`, `ComposedTrainingTests`, `WorkoutGeneratorTests` blijven ongewijzigd groen).
- Geen hardcoded teksten: `t()` met sleutels uit `Fitling/Resources/Localizable.xcstrings` (alle `training.*`, `body.*`, `photos.*` bestaan al).
- Gedeelde rijen (`owner_id` null) zijn alleen-lezen; eigen rijen krijgen een client-UUID, `updated_at` = klok van de client, verwijderen = `deleted_at` zetten.
- Voortgangsfoto's verlaten het apparaat nooit (schema.sql): op het web in IndexedDB, nooit naar Supabase.
- Apple Health (`training.health.*`) bestaat niet op het web (spec-besluit 3): die sectie ontbreekt.
- Gewicht in kg of lb naar de taal/regio van de browser (en-US → lb), opgeslagen altijd in kg (WeightUnit op iOS).
- "Beweging beperken": oefenanimaties tonen begin- en eindbeeld, de rusttimer telt zonder animatie.
- Elke commit eindigt met `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; een commit die iOS raakt krijgt `[ios]` in de kop van de laatste push.

## Review Focus

- Een training die op twee apparaten openstaat: sets van het andere apparaat staan erbij (iOS voegt hun oefeningen toe); het web doet hetzelfde. Test in Task 5 (`setsFromAnotherDeviceAreShown`).
- Een gedeeld schema kan niet worden aangepast, alleen gekopieerd. Test in Task 4 (`sharedProgramsCannotBeChanged`).
- Een set zonder gewicht of herhalingen kan niet worden gelogd; extreme waarden worden begrensd zoals `TrainingStore.log`. Test in Task 1 en Task 5.
- Een gebruiker met honderden trainingen: alle sets tellen mee voor advies en records (lezen per pagina van 1000). Test in Task 3.
- 200 % tekst en donker op elk nieuw scherm: niets buiten beeld, geen axe-fouten. Test in Task 7.

---

### Task 1: TrainingRecords in FitlingCore, iOS roept hem aan [ios]

**Files:**
- Create: `Packages/FitlingCore/Sources/FitlingCore/TrainingRecords.swift`, `Packages/FitlingCore/Tests/FitlingCoreTests/TrainingRecordsTests.swift`
- Modify: `Fitling/Data/TrainingStore.swift`, `Fitling/Features/Training/WorkoutViewModel.swift`, `Fitling/Features/Training/ProgressViews.swift` (VolumeView.load)

**Interfaces:**
- Produces (public in FitlingCore):
  - Rijen: `ExerciseRecord {id, ownerID?, name: LocalizedText, kind, loadType, equipment, primaryMuscles, secondaryMuscles, defaultStepKg}`, `ProgramRecord {id, ownerID?, name, daysPerWeek}`, `ProgramDayRecord {id, programID, ownerID?, name, position, updatedAt: Double}`, `ProgramItemRecord {id, programDayID, exerciseID, position, targetSets, repMin, repMax, restSeconds}`, `ExerciseSettingRecord {exerciseID, stepKg, repMin?, repMax?, updatedAt}`, `SessionRecord {id, programDayID?, performedOn: Day, startedAt: Double, endedAt: Double?}`, `SetRecord {id, sessionID, exerciseID, position, weightKg, reps, rpe?, isWarmup}` — alleen niet-verwijderde rijen; tijden in seconden sinds 1970.
  - `struct TrainingRecords { init(userID:, exercises:, programs:, days:, items:, settings:, sessions:, sets:, today: Day, languages: [String]) }` met de leesfuncties van `TrainingStore`, dezelfde namen en volgorde: `programs()`, `days(of:)`, `items(of:)`, `exercises()`, `composedWorkoutCount(of:)`, `canChange(_:)`, `activeSession()`, `finishedSessions(limit:)`, `sets(of:)`, `daysToShow(of:)`, `nextWorkout() -> NextWorkoutRecord?` (`.programDay(programID, dayID)` / `.compose(TrainingFocus)`), `history(of:excluding:)`, `setting(for:)`, `rules(for:in:)`, `rulesOfLastWorkout(for:)`, `adviceAfterLastWorkout(for:)`, `advice(for:in:excluding:)`, `workoutCandidates()`, `workoutHistory()`, `coachNotes(limit:) -> [CoachNoteRecord]` (`exerciseID`, `.heavier(ProgressionAdvice)` / `.switchTo(UUID)`), `prefill(exerciseID:item:excluding:) -> SetDraft {weightKg?, reps?}`, `records(in sessionID:, exerciseIDs:)`, `weeklyVolume() -> [Day: [MuscleGroup: MuscleVolume]]`.
  - `TrainingRecords.loggedSet(weightKg:reps:rpe:) -> (weightKg: Double, reps: Int, rpe: Double?)`: de begrenzing van `TrainingStore.log` (gewicht op 0,01 en 0…1000, reps 0…1000, RPE op 0,5 en 1…10).
- iOS: `TrainingStore` bouwt `records()` uit SwiftData en laat de leesfuncties die waarde gebruiken; schrijven blijft in `TrainingStore`. `WorkoutViewModel.prefill` en `records()` en `VolumeView.load` lezen via `TrainingRecords`.

- [ ] **Step 1:** `TrainingRecordsTests` rood: `theNextWorkoutFollowsTheLastOne`, `afterAComposedWorkoutTheNextFocusIsComposed`, `historyIgnoresWarmUpsAndOrdersByDayThenStart`, `rulesPreferTheUsersSettingThenTheProgramme`, `keepGoingAimsForOneMoreRep`, `loggedSetsAreBounded`, `theCoachSaysWhatCanGoHeavierAndWhatHasStalled`, `composedDaysShowNewestFirstAndAtMostTen` (verwachtingen overgenomen uit `FitlingTests/TrainingTests.swift` en `ComposedTrainingTests.swift`).
- [ ] **Step 2:** commit rood, push, zie FitlingCore rood in CI.
- [ ] **Step 3:** `TrainingRecords.swift` bouwen door de leesfuncties van `TrainingStore` over te zetten op arrays; `TrainingStore`, `WorkoutViewModel`, `VolumeView` erop laten leunen.
- [ ] **Step 4:** commit met `[ios]`, CI: core, web-core en iOS groen (iOS-trainingstests ongewijzigd).

### Task 2: De brug voor Training

**Files:** Create `web/core/Sources/FitlingWeb/TrainingCalls.swift`; Modify `Calls.swift` (dispatch), `web/core/Tests/FitlingWebTests/CallsTests.swift`, `web/src/core/fitlingCore.ts` (+ test).

**Interfaces:**
- Invoer `TrainingInput` = de rijen als JSON (`exercises`, `programs`, `days`, `items`, `settings`, `sessions`, `sets`, met `name` als `{nl, en, de}`), plus `userID`, `today`, `languages`.
- Aanroepen:
  - `trainingOverview(TrainingInput) -> {programs: [{id, name, detail: {kind: "shared"|"composed"|"own", count}}], activeSessionID?, next?: {kind:"programDay", programID, dayID} | {kind:"compose", focus}, recent: [{sessionID, dayID?, startedOn, setCount}], coach: [{exerciseID, kind:"heavier", advice} | {exerciseID, kind:"switchTo", otherID}]}`;
  - `programDetail(TrainingInput & {programID}) -> {days: [{id, name, canChange, items: [{id, exerciseID, targetSets, repMin, repMax, restSeconds}]}]}` (`daysToShow`);
  - `workout(TrainingInput & {sessionID}) -> {entries: [{exerciseID, itemID?, restSeconds, rules, advice, draft: {weightKg?, reps?}}], sets}`;
  - `workoutRecords(TrainingInput & {sessionID}) -> [{exerciseID, record}]`;
  - `composePlan(TrainingInput & {focus, minutes}) -> WorkoutPlan` en `trainingDurations() -> {durations, defaultMinutes}`;
  - `exerciseProgress(TrainingInput & {exerciseID}) -> {points: [{day, weightKg, oneRepMaxKg?}], records, advice, stepKg}`;
  - `weeklyVolume(TrainingInput) -> [{weekStart, muscles: [{muscle, sets, tonnageKg}]}]`;
  - `loggedSet({weightKg, reps, rpe?}) -> {weightKg, reps, rpe?}`;
  - `bodyMeasurementRules()` en `bodyMeasurement({kind, value, day, today, unit}) -> {valid, valueStored}` (BodyLog-regels, als die in de app staan: eerst naar FitlingCore).
- Advies als `{kind, weightKg?, targetReps?}`.

- [ ] Rood: `trainingOverviewIsTheStoresOwn`, `workoutPrefillsFromTheAdvice`, `loggedSetIsBounded`, `exerciseProgressListsEveryWorkout`; dan bouwen; CI web-core groen.

### Task 3: Training en lichaam lezen en schrijven op het web

**Files:** Create `web/src/data/training.ts`, `web/src/data/body.ts`, `web/src/data/photos.ts` (+ `training.test.ts`, `body.test.ts` tegen de lokale Supabase, `photos.test.ts` met fake-indexeddb niet: een kleine eigen opslag-interface met een nep in de test).

**Interfaces:**
- `loadTraining(client, userID): Promise<TrainingInputRows>` (alle eigen en gedeelde rijen, per pagina van 1000, zonder verwijderde).
- Schrijven, elk met `now: Date`: `createProgram`, `copyProgram`, `renameProgram`, `deleteProgram`, `addItem`, `updateItem`, `removeItem`, `startWorkout(dayID?) -> sessionID`, `logSet`, `removeSet`, `finishWorkout`, `discardWorkout` (met de samengestelde dag als die verder ongebruikt is), `composeWorkout(plan, focus, names) -> dayID` (de dag-id is `ComposedWorkout.dayID(for:)` via de brug), `saveStep`.
- Lichaam: `loadMeasurements`, `addMeasurement`, `deleteMeasurement`. Foto's: `PhotoStore` op IndexedDB (`list`, `add(blob, day)`, `remove`).

- [ ] Rood: `copyingAProgramMakesItYours`, `discardingRemovesTheSetsAndTheComposedDay`, `manyWorkoutsAreReadInPages`, `measurementsAreSavedAndDeleted`; bouwen; CI groen.

### Task 4: Tabblad Training en de schema's

**Files:** Create `web/src/screens/Training.tsx`, `ProgramDetail.tsx`, `NewProgram.tsx`, `ExercisePicker.tsx`; Modify `web/src/Home.tsx`; Test `web/e2e/training.spec.ts`.

Nagebouwd naar `TrainingTabView.swift` en `ProgramDetailView.swift`: verder gaan of de volgende training, samenstellen en de coach, schema's (gedeeld, samengesteld, eigen), voortgang (oefeningen, volume, lichaam, foto's), recente trainingen; een schema met dagen en oefeningen, hernoemen, verwijderen, kopiëren, oefening toevoegen/aanpassen/verwijderen. Navigatie met `useHistoryStack`.

- [ ] Rood: `theNextWorkoutIsOffered`, `sharedProgramsCannotBeChanged`, `aNewProgramHasItsDays`, `exercisesAreAddedToADay`, `theCoachNamesWhatCanGoHeavier`; bouwen; CI groen.

### Task 5: Samenstellen en een training loggen

**Files:** Create `web/src/screens/ComposeWorkout.tsx`, `Workout.tsx`, `web/src/ui/RestTimer.tsx`; Test `web/e2e/workout.spec.ts`.

Nagebouwd naar `ComposeWorkoutView.swift`, `WorkoutView.swift`: tijd en focus, het plan met tijd; per oefening de sets, het advies en een conceptset (gewicht, reps, RPE, opwarmset), loggen start de rusttimer, overslaan, set verwijderen, oefening toevoegen, later verder, weggooien, afronden met records.

- [ ] Rood: `aComposedWorkoutStartsAndIsLogged`, `aSetNeedsWeightAndReps`, `restTimerStartsAfterAWorkingSet`, `finishingShowsTheRecords`, `discardingRemovesTheWorkout`, `setsFromAnotherDeviceAreShown`; bouwen; CI groen.

### Task 6: Voortgang, volume, lichaam en foto's

**Files:** Create `web/src/screens/ExerciseProgress.tsx` (lijst en detail), `Volume.tsx`, `Body.tsx`, `Photos.tsx`, `web/src/ui/LineChart.tsx`, `web/src/ui/BarChart.tsx`, `web/src/ui/ExerciseAnimation.tsx`; Test `web/e2e/progress.spec.ts`.

Nagebouwd naar `ProgressViews.swift`, `BodyViews.swift`, `ExerciseAnimationView.swift`: grafiek van gewicht en geschat 1RM, records, eigen gewichtsstap, uitleg en animatie (sprite-sheet uit `public/exercises`, `ExerciseAnimations.json`); volume deze/vorige week per spiergroep; lichaamsmetingen per soort met grafiek, toevoegen en geschiedenis; foto's kiezen, bekijken, verwijderen, alleen op dit apparaat.

- [ ] Rood: `progressShowsEveryWorkout`, `theStepIsSaved`, `volumeCountsTheWeek`, `measurementsAreAddedAndShown`, `photosStayOnThisDevice`, `animationStandsStillWithReduceMotion`; bouwen; CI groen.

### Task 7: Audit, borden, review, PR

- [ ] Audit (`audit.spec.ts`): elk nieuw scherm in licht, donker en 200 %.
- [ ] Vergelijkingsborden met de iOS-screenshots (`rondleiding-*`, `licht-*`) in `.impeccable/review/web-fase-4/`, naar de gebruiker.
- [ ] Eindreview (subagent, opus), fixronde met rood-groen, kleine punten naar UNFORGET.
- [ ] PR `web-fase-4` → `web-fase-3`.
