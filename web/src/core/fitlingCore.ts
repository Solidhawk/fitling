import { ConsoleStdout, File, OpenFile, WASI } from "@bjorn3/browser_wasi_shim";

/** A day as Postgres writes it: "2026-11-18". */
export type IsoDay = string;

export interface DailyPlanInput {
  birthDay: IsoDay;
  sex: "male" | "female" | "other";
  heightCm: number;
  weightKg: number;
  activityLevel: "sedentary" | "light" | "moderate" | "active" | "very_active";
  goal: "lose" | "build_muscle" | "maintain" | "recomp";
  today: IsoDay;
}

export interface DailyPlan {
  bmr: number;
  tdee: number;
  targets: { kcal: number; proteinG: number; carbsG: number; fatG: number };
  floorApplied: boolean;
  warnings: string[];
}

export interface Targets {
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
}

export interface BodyFields {
  centimetres?: number;
  feet?: number;
  inches?: number;
  /** Kilograms or pounds, following usesMetric. */
  weight?: number;
}

export interface BodyInputAnswer {
  fields: BodyFields;
  heightCm?: number;
  weightKg?: number;
  heightValid: boolean;
  weightValid: boolean;
  isValid: boolean;
}

export type Sex = DailyPlanInput["sex"];
export type Goal = DailyPlanInput["goal"];
export type Activity = DailyPlanInput["activityLevel"];

export type QuantityUnit = "g" | "ml" | "serving";

/** Per 100 g or 100 ml, or what one entry adds; undefined is unknown. */
export interface Nutrients {
  kcal?: number;
  proteinG?: number;
  carbsG?: number;
  fatG?: number;
}

export interface PortionAnswer {
  units: QuantityUnit[];
  defaultUnit: QuantityUnit;
  defaultQuantity: number;
  preview?: Required<Pick<Nutrients, "kcal">> & Nutrients;
  needsKcal: boolean;
  canSave: boolean;
}

export interface OwnProductFields {
  name: string;
  brand?: string;
  gtin?: string;
  quantityUnit: "g" | "ml";
  servingSize?: number;
  kcal100: number;
  protein100?: number;
  carbs100?: number;
  fat100?: number;
  searchName: string;
}

export interface DayTotals {
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  entryCount: number;
  unknownProtein: number;
  unknownCarbs: number;
  unknownFat: number;
}

export type Mood = "happy" | "content" | "sluggish" | "tired" | "hungry" | "asleep";

/** The `creatures` row as FitlingCore reads it. */
export interface CreatureStateInput {
  species: string;
  colorIndex: number;
  tone: string;
  createdOn: IsoDay;
  bodyShape: number;
  xp: number;
  lastProcessedDay?: IsoDay;
  offTargetDays: number;
}

export interface PartnerSnapshot {
  mood: Mood;
  condition: string;
  energy: number;
  level: number;
  xp: number;
  xpIntoLevel: number;
  /** 0 at the highest level. */
  xpForNextLevel: number;
  growthStage: number;
  bodyShape: number;
  colorIndex: number;
  trainedRecently: boolean;
  unlockedItems: string[];
  /** Every accessory in its own order, with the level at which it unlocks. */
  items: { item: string; unlockLevel: number }[];
  unlockedColorCount: number;
  /** The levels at which the colours that are still locked unlock. */
  lockedColorLevels: number[];
  /** What today earns so far; it is added once the day is over. */
  todayXP: { logging: number; withinTarget: number; protein: number; workout: number };
  /** How many days before today decide the mood. */
  historyDays: number;
}

/** What happened when finished days were folded in: a level, an accessory, a colour, a recovery bonus. */
export interface PartnerEvent {
  kind: "leveledUp" | "unlockedItem" | "unlockedColor" | "recoveryBonus";
  level?: number;
  item?: string;
  index?: number;
  xp?: number;
}

/** The partner's days, as partnerSnapshot and partnerAdvance read them. */
/** A name or text in several languages, as jsonb stores it: {"nl": "Bankdrukken", "en": "Bench press"}. */
export type Localized = Record<string, string>;

/** The user's training rows and the shared catalogue, as TrainingRecords in FitlingCore reads them. */
export interface TrainingInput {
  userID: string;
  today: IsoDay;
  languages: string[];
  exercises: {
    id: string;
    ownerID?: string;
    name: Localized;
    kind: string;
    loadType: string;
    primaryMuscles: string[];
    secondaryMuscles: string[];
    defaultStepKg: number;
  }[];
  /** Also removed ones (`deleted`), as a past workout keeps the name of its day. */
  programs: { id: string; ownerID?: string; name: Localized; daysPerWeek: number; deleted: boolean }[];
  days: { id: string; programID: string; ownerID?: string; name: Localized; position: number; updatedAt: number; deleted: boolean }[];
  items: {
    id: string;
    programDayID: string;
    ownerID?: string;
    exerciseID: string;
    position: number;
    targetSets: number;
    repMin: number;
    repMax: number;
    restSeconds: number;
  }[];
  settings: { exerciseID: string; stepKg: number; repMin?: number; repMax?: number; updatedAt: number }[];
  /** Times in seconds since 1970. */
  sessions: { id: string; programDayID?: string; performedOn: IsoDay; startedAt: number; endedAt?: number }[];
  sets: { id: string; sessionID: string; exerciseID: string; position: number; weightKg: number; reps: number; rpe?: number; isWarmup: boolean }[];
}

/** What the coach or the workout advises (ProgressionAdvice). */
export interface Advice {
  kind: "findStartingWeight" | "keepGoing" | "increase" | "addRepsFirst" | "reduce" | "easeBackIn" | "makeHarder" | "makeEasier";
  weightKg?: number;
  targetReps?: number;
}

export interface PersonalRecord {
  kind: "weight" | "estimatedOneRepMax" | "reps";
  kg: number;
  count?: number;
}

export interface SessionSummary {
  id: string;
  title?: string;
  startedAt: number;
  setCount: number;
}

export interface TrainingOverview {
  programs: { id: string; name: string; shared: boolean; daysPerWeek: number; composedCount?: number }[];
  active?: SessionSummary;
  next?: { kind: "programDay" | "compose"; programID?: string; dayID?: string; dayName?: string; programName?: string; focus?: string };
  recent: SessionSummary[];
  coach: { exerciseID: string; name: string; kind: "heavier" | "switchTo"; advice?: Advice; otherID?: string; otherName?: string }[];
}

export interface ProgramDetail {
  id: string;
  name: string;
  own: boolean;
  days: {
    id: string;
    name: string;
    composed: boolean;
    updatedAt: number;
    canChange: boolean;
    items: { id: string; exerciseID: string; exerciseName: string; targetSets: number; repMin: number; repMax: number; restSeconds: number }[];
  }[];
}

export interface WorkoutEntry {
  exerciseID: string;
  name: string;
  itemID?: string;
  restSeconds: number;
  rules: { repMin: number; repMax: number; targetSets: number; stepKg: number };
  advice: Advice;
  /** In the user's unit. */
  draft: { weight?: number; reps?: number };
}

export interface WorkoutPlan {
  exercises: { exerciseID: string; name: string; sets: number; repMin: number; repMax: number; restSeconds: number }[];
  minutes: number;
  roundedMinutes: number;
  leavesTimeOver: boolean;
  leftOut: string[];
  dayID: string;
  programID?: string;
}

export interface ExerciseProgress {
  points: { day: IsoDay; kg: number }[];
  heaviestKg?: number;
  bestOneRepMaxKg?: number;
  workouts: number;
  advice: Advice;
  stepKg: number;
}

export type MeasurementKind = "weight" | "waist" | "chest" | "hips" | "arm" | "thigh" | "neck";

/** The recipes, week menu and preferences of the user and the shared recipes, as MenuBook in FitlingCore reads them. */
/** A shared recipe or one of the user's own, as MenuBook reads it (MenuRecipe). */
export interface MenuRecipe {
  id: string;
  ownerID?: string;
  title: Localized;
  servings: number;
  cookMinutes: number;
  kcalPerServing: number;
  proteinGPerServing: number;
  carbsGPerServing: number;
  fatGPerServing: number;
  costCentsPerServing?: number;
  keepsWell: boolean;
  mealSlots: string[];
  tags: string[];
  /** The products in it, for what the user leaves out. */
  productIDs: string[];
}

export interface MenuInput {
  userID: string;
  today: IsoDay;
  languages: string[];
  recipes: MenuRecipe[];
  /** Removed after they were planned: their meals keep name and values, but they are no longer offered or planned. */
  removedRecipes: MenuRecipe[];
  entries: {
    id: string;
    plannedOn: IsoDay;
    meal: string;
    recipeID: string;
    servings: number;
    isLeftover: boolean;
    isPinned: boolean;
    loggedEntryID?: string;
  }[];
  settings: MenuPreferences;
  excludedProductIDs: string[];
}

/** What the user wants in a menu (menu_preferences). */
export interface MenuPreferences {
  excludedTags: string[];
  maxCookMinutes?: number;
  budgetCents?: number;
  mealPrep: boolean;
  mealSlots: string[];
}

export interface RecipeSummary {
  id: string;
  title: string;
  kcalPerServing: number;
  cookMinutes: number;
  own: boolean;
  mealSlots: string[];
}

export interface MenuOverview {
  days: {
    day: IsoDay;
    entries: { id: string; slot: string; recipeID: string; title: string; servings: number; kcal: number; isPinned: boolean; logged: boolean }[];
  }[];
  recipes: RecipeSummary[];
}

/** What the planner could not solve (MenuIssue). */
export interface MenuIssue {
  kind: "noRecipes" | "kcalOutOfRange" | "proteinShort" | "overBudget";
  slot?: string;
  day?: IsoDay;
  kcal?: number;
  missingG?: number;
  byCents?: number;
}

export interface MenuChange {
  removed: string[];
  added: { day: IsoDay; slot: string; recipeID: string; servings: number; isLeftover: boolean }[];
  issues: MenuIssue[];
}

export interface LoggedMeal {
  recipeID: string;
  name: string;
  day: IsoDay;
  slot: string;
  servings: number;
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
}

/** An item on the shopping list (shopping_items), as ShoppingBook reads it. */
export interface ShoppingItemRow {
  id: string;
  name: string;
  quantity?: number;
  unit?: string;
  aisle: string;
  productID?: string;
  isChecked: boolean;
  /** manual, or menu for what the week menu put on the list. */
  source: string;
}

/** An offer the backend collected (offers), as far as matching needs it. */
export interface OfferRow {
  id: string;
  supermarketID: string;
  title: string;
  brand?: string;
  gtin?: string;
  quantityValue?: number;
  quantityUnit?: string;
  priceCents: number;
  validFrom: IsoDay;
  validTo: IsoDay;
}

export interface ShoppingInput {
  today: IsoDay;
  items: ShoppingItemRow[];
  offers: OfferRow[];
  supermarkets: { id: string; name: string }[];
  favoriteSupermarketIDs: string[];
  /** Uncertain offers the user said are right, kept on the device. */
  confirmedOfferIDs: string[];
}

export interface ShoppingOverview {
  items: {
    id: string;
    name: string;
    quantity?: number;
    unit?: string;
    isChecked: boolean;
    source: string;
    offer?: { offerID: string; priceCents: number; supermarketID: string; supermarketName: string; validTo: IsoDay };
  }[];
  totals: { supermarketID: string; name: string; totalCents: number; itemsWithoutPrice: number }[];
  questions: { id: string; itemName: string; offerTitle: string; supermarketNames: string[]; offerIDs: string[] }[];
}

/** One line of a recipe (recipe_ingredients), for what the week menu needs. */
export interface RecipeIngredientRow {
  recipeID: string;
  productID?: string;
  name: Localized;
  quantity: number;
  unit: string;
  aisle: string;
  position: number;
}

/** An item as it goes on the list: a name of at most 120 characters, an amount only with a quantity. */
export interface NewShoppingItem {
  name: string;
  quantity?: number;
  unit?: string;
  aisle: string;
  productID?: string;
}

export interface PartnerDays {
  creature: CreatureStateInput;
  entries: { day: IsoDay; kcal: number; proteinG?: number }[];
  workoutDays: IsoDay[];
  periods: { effectiveOn: IsoDay; updatedAtMs: number; targets: Targets }[];
  fallback: Targets;
  today: IsoDay;
}

/** When the partner may send a reminder, kept per browser (ReminderSettings): minutes after midnight. */
export interface ReminderSettings {
  isOn: boolean;
  times: number[];
}

/** One reminder: on `day` at `minutes` after midnight where the user is, with the catalog key of its text. */
export interface PlannedReminder {
  identifier: string;
  day: IsoDay;
  minutes: number;
  messageKey: string;
}

export interface ProfileRules {
  activityFactors: Record<Activity, number>;
  proteinPerKg: Record<Goal, number>;
  /** Lowest and highest value of each target the user may type. */
  targetLimits: Record<keyof Targets, [number, number]>;
}

/** The rules of FitlingCore, the same code as in the iOS app (D-24). */
export interface FitlingCore {
  dailyPlan(input: DailyPlanInput): DailyPlan;
  bodyInput(input: { usesMetric: boolean; stored?: { heightCm: number; weightKg: number }; fields?: BodyFields }): BodyInputAnswer;
  birthDay(input: { birthDay: IsoDay; today: IsoDay }): { age: number; isAdult: boolean; isValid: boolean };
  macros(input: { kcal: number; weightKg: number; goal: Goal }): Targets;
  kcalShares(targets: Targets): { protein: number; carbs: number; fat: number };
  warnings(input: { kcal: number; bmr: number; tdee: number; sex: Sex }): { warnings: string[]; commonMinimumKcal: number };
  targetsOnDay(input: { day: IsoDay; fallback: Targets; periods: { effectiveOn: IsoDay; updatedAtMs: number; targets: Targets }[] }): Targets;
  creature(input: { level: number }): { startShape: number; colorCount: number; growthStage: number };
  goalFactors(): Record<Goal, number>;
  profileRules(): ProfileRules;
  searchKey(input: { text: string }): { key: string };
  barcode(input: { text: string }): { gtin?: string };
  recentProducts(input: { logged: { productID: string; updatedAtMs: number }[] }): { ids: string[]; limit: number };
  portion(input: {
    quantityUnit: string;
    servingSize?: number;
    per100: Nutrients;
    quantity?: number;
    unit?: QuantityUnit;
    kcalOnPackage?: number;
  }): PortionAnswer;
  logEntry(input: { name: string; quantity: number; unit: QuantityUnit; servingSize?: number; per100: Nutrients }): {
    name: string;
    quantity: number;
    nutrients: Required<Pick<Nutrients, "kcal">> & Nutrients;
  } | null;
  ownProduct(input: {
    name: string;
    brand: string;
    gtin: string;
    isMillilitre: boolean;
    kcal?: number;
    protein?: number;
    carbs?: number;
    fat?: number;
    servingSize?: number;
  }): { fields?: OwnProductFields };
  dayTotals(input: { entries: Nutrients[] }): DayTotals;
  localizedText(input: { values: Record<string, string>; languages: string[] }): { text: string };
  partnerSnapshot(input: PartnerDays): PartnerSnapshot;
  advanceFrom(input: { creature: CreatureStateInput }): { firstDay: IsoDay };
  partnerAdvance(input: PartnerDays): { creature: CreatureStateInput; changed: boolean; events: PartnerEvent[] };
  wearing(input: { worn: string[]; item: string; unlocked: string[] }): { worn: string[] };
  trainingOverview(input: { training: TrainingInput }): TrainingOverview;
  programDetail(input: { training: TrainingInput; programID: string }): ProgramDetail;
  trainingExercises(input: { training: TrainingInput }): { id: string; name: string; kind: string; primaryMuscles: string[]; done: boolean }[];
  workout(input: { training: TrainingInput; sessionID: string; added: string[]; usesPounds: boolean }): { title?: string; entries: WorkoutEntry[] };
  workoutRecords(input: { training: TrainingInput; sessionID: string; exerciseIDs: string[] }): { exerciseID: string; name: string; record: PersonalRecord }[];
  loggedSet(input: { weight?: number; reps?: number; rpe?: number; usesPounds: boolean }): { canLog: boolean; weightKg: number; reps: number; rpe?: number };
  discardCleanup(input: { training: TrainingInput; sessionID: string }): { dayID?: string; itemIDs: string[]; programID?: string };
  composePlan(input: { training: TrainingInput; focus: string; minutes: number }): WorkoutPlan;
  trainingChoices(): { durations: number[]; defaultMinutes: number; shortWorkoutMinutes: number; focuses: { id: string; muscles: string[] }[] };
  exerciseProgress(input: { training: TrainingInput; exerciseID: string }): ExerciseProgress;
  weeklyVolume(input: { training: TrainingInput; lastWeek: boolean }): { muscle: string; sets: number }[];
  measurementStored(input: { value: number; kind: MeasurementKind; usesMetric: boolean }): { value?: number };
  measurementShown(input: { value: number; kind: MeasurementKind; usesMetric: boolean }): { value?: number };
  menuOverview(input: { menu: MenuInput }): MenuOverview;
  /** `seed` is a UInt64 as text. */
  menuGenerate(input: { menu: MenuInput; days: number; seed: string; targets: Targets }): MenuChange;
  menuRenew(input: { menu: MenuInput; day: IsoDay; seed: string; targets: Targets }): MenuChange;
  menuLoggedMeal(input: { menu: MenuInput; entryID: string }): { meal?: LoggedMeal };
  menuRecipesFor(input: { menu: MenuInput; entryID: string }): RecipeSummary[];
  ownRecipeComplete(input: {
    title: string;
    servings: number;
    cookMinutes: number;
    kcal?: number;
    protein?: number;
    carbs?: number;
    fat?: number;
    mealSlots: string[];
  }): { complete: boolean };
  /** The amount as `recipe_ingredients` keeps it; none for an amount it refuses. */
  storedIngredientQuantity(input: { quantity: number }): { quantity?: number };
  shoppingOverview(input: { shopping: ShoppingInput }): ShoppingOverview;
  shoppingRefill(input: { shopping: ShoppingInput; menu: MenuInput; ingredients: RecipeIngredientRow[] }): {
    removed: string[];
    added: NewShoppingItem[];
  };
  shoppingNewItem(input: { text: string }): { item?: NewShoppingItem };
  /** The reminders for today and tomorrow (ReminderPlanner), each with what the partner would say that day. */
  remindersPlan(input: { settings: ReminderSettings; minutesNow: number; days: PartnerDays }): { reminders: PlannedReminder[] };
  /** No reminders from `quietFrom` until `quietUntil`, minutes after midnight (ReminderSettings). */
  reminderRules(): { quietFrom: number; quietUntil: number; maximumPerDay: number };
}

interface Exports {
  memory: WebAssembly.Memory;
  fitling_alloc(size: number): number;
  fitling_free(pointer: number, size: number): void;
  fitling_call(pointer: number, length: number): bigint;
}

/** One request to a running copy, and its answer as text. */
function exchange(exports: Exports, fn: string, input: unknown): string {
  const request = new TextEncoder().encode(JSON.stringify({ fn, input }));
  const pointer = exports.fitling_alloc(request.length);
  new Uint8Array(exports.memory.buffer, pointer, request.length).set(request);
  const packed = exports.fitling_call(pointer, request.length);
  exports.fitling_free(pointer, request.length);
  const answerPointer = Number(packed >> 32n);
  const answerLength = Number(packed & 0xffffffffn);
  // Read before freeing: the memory may grow, so take the buffer anew.
  const answer = new TextDecoder().decode(new Uint8Array(exports.memory.buffer, answerPointer, answerLength).slice());
  exports.fitling_free(answerPointer, answerLength);
  return answer;
}

/** A running copy of the rules, with its own memory; Swift writes why it stopped to stderr (console.warn). */
async function start(module: WebAssembly.Module): Promise<Exports> {
  const wasi = new WASI([], [], [
    new OpenFile(new File([])),
    ConsoleStdout.lineBuffered((line) => console.log(line)),
    ConsoleStdout.lineBuffered((line) => console.warn(line)),
  ]);
  const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi.wasiImport });
  wasi.initialize(instance as { exports: { memory: WebAssembly.Memory; _initialize?: () => unknown } });
  return instance.exports as unknown as Exports;
}

/** Loads the WebAssembly built from web/core. Every call sends JSON and gets JSON back. */
export async function loadCore(wasm: ArrayBuffer): Promise<FitlingCore> {
  const module = await WebAssembly.compile(wasm);
  let exports: Exports | undefined = await start(module);
  let replacing: Promise<void> | undefined;

  /**
   * A trap stops the module halfway (its stack, a value half made), so it is not called again: a fresh copy of the
   * same module takes over. That takes a moment, as Chrome does not start a module this big at once on the page.
   */
  function replace() {
    exports = undefined;
    replacing ??= start(module).then(
      (fresh) => {
        exports = fresh;
        replacing = undefined;
      },
      () => {
        replacing = undefined;
      },
    );
  }

  function call(fn: string, input: unknown): unknown {
    if (!exports) {
      replace();
      throw new Error("error.server");
    }
    let answer: string;
    try {
      answer = exchange(exports, fn, input);
    } catch (error) {
      // A trap, or a stack that ran out inside the module.
      if (!(error instanceof WebAssembly.RuntimeError || error instanceof RangeError)) throw error;
      console.error(`fitling-core ${fn}: ${error.message}`);
      replace();
      throw new Error("error.server");
    }
    // A call can answer null (logEntry for an amount that cannot be worked out).
    const result = JSON.parse(answer) as { error?: string } | null;
    if (result !== null && typeof result.error === "string") throw new Error(result.error);
    return result;
  }

  return {
    dailyPlan: (input) => call("dailyPlan", input) as DailyPlan,
    bodyInput: (input) => call("bodyInput", input) as BodyInputAnswer,
    birthDay: (input) => call("birthDay", input) as ReturnType<FitlingCore["birthDay"]>,
    macros: (input) => call("macros", input) as Targets,
    kcalShares: (targets) => call("kcalShares", targets) as ReturnType<FitlingCore["kcalShares"]>,
    warnings: (input) => call("warnings", input) as ReturnType<FitlingCore["warnings"]>,
    targetsOnDay: (input) => call("targetsOnDay", input) as Targets,
    creature: (input) => call("creature", input) as ReturnType<FitlingCore["creature"]>,
    goalFactors: () => call("goalFactors", {}) as Record<Goal, number>,
    profileRules: () => call("profileRules", {}) as ProfileRules,
    searchKey: (input) => call("searchKey", input) as ReturnType<FitlingCore["searchKey"]>,
    barcode: (input) => call("barcode", input) as ReturnType<FitlingCore["barcode"]>,
    recentProducts: (input) => call("recentProducts", input) as ReturnType<FitlingCore["recentProducts"]>,
    portion: (input) => call("portion", input) as PortionAnswer,
    logEntry: (input) => call("logEntry", input) as ReturnType<FitlingCore["logEntry"]>,
    ownProduct: (input) => call("ownProduct", input) as ReturnType<FitlingCore["ownProduct"]>,
    dayTotals: (input) => call("dayTotals", input) as DayTotals,
    partnerSnapshot: (input) => call("partnerSnapshot", input) as PartnerSnapshot,
    advanceFrom: (input) => call("advanceFrom", input) as { firstDay: IsoDay },
    partnerAdvance: (input) => call("partnerAdvance", input) as ReturnType<FitlingCore["partnerAdvance"]>,
    wearing: (input) => call("wearing", input) as { worn: string[] },
    trainingOverview: (input) => call("trainingOverview", input) as TrainingOverview,
    programDetail: (input) => call("programDetail", input) as ProgramDetail,
    trainingExercises: (input) => call("trainingExercises", input) as ReturnType<FitlingCore["trainingExercises"]>,
    workout: (input) => call("workout", input) as ReturnType<FitlingCore["workout"]>,
    workoutRecords: (input) => call("workoutRecords", input) as ReturnType<FitlingCore["workoutRecords"]>,
    loggedSet: (input) => call("loggedSet", input) as ReturnType<FitlingCore["loggedSet"]>,
    discardCleanup: (input) => call("discardCleanup", input) as ReturnType<FitlingCore["discardCleanup"]>,
    composePlan: (input) => call("composePlan", input) as WorkoutPlan,
    trainingChoices: () => call("trainingChoices", {}) as ReturnType<FitlingCore["trainingChoices"]>,
    exerciseProgress: (input) => call("exerciseProgress", input) as ExerciseProgress,
    weeklyVolume: (input) => call("weeklyVolume", input) as ReturnType<FitlingCore["weeklyVolume"]>,
    measurementStored: (input) => call("measurementStored", input) as { value?: number },
    measurementShown: (input) => call("measurementShown", input) as { value?: number },
    menuOverview: (input) => call("menuOverview", input) as MenuOverview,
    menuGenerate: (input) => call("menuGenerate", input) as MenuChange,
    menuRenew: (input) => call("menuRenew", input) as MenuChange,
    menuLoggedMeal: (input) => call("menuLoggedMeal", input) as { meal?: LoggedMeal },
    menuRecipesFor: (input) => call("menuRecipesFor", input) as RecipeSummary[],
    ownRecipeComplete: (input) => call("ownRecipeComplete", input) as { complete: boolean },
    storedIngredientQuantity: (input) => call("storedIngredientQuantity", input) as { quantity?: number },
    shoppingOverview: (input) => call("shoppingOverview", input) as ShoppingOverview,
    shoppingRefill: (input) => call("shoppingRefill", input) as { removed: string[]; added: NewShoppingItem[] },
    shoppingNewItem: (input) => call("shoppingNewItem", input) as { item?: NewShoppingItem },
    remindersPlan: (input) => call("remindersPlan", input) as { reminders: PlannedReminder[] },
    reminderRules: () => call("reminderRules", {}) as { quietFrom: number; quietUntil: number; maximumPerDay: number },
    localizedText: (input) => call("localizedText", input) as { text: string },
  };
}
