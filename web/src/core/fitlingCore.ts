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
export interface PartnerDays {
  creature: CreatureStateInput;
  entries: { day: IsoDay; kcal: number; proteinG?: number }[];
  workoutDays: IsoDay[];
  periods: { effectiveOn: IsoDay; updatedAtMs: number; targets: Targets }[];
  fallback: Targets;
  today: IsoDay;
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
}

interface Exports {
  memory: WebAssembly.Memory;
  fitling_alloc(size: number): number;
  fitling_free(pointer: number, size: number): void;
  fitling_call(pointer: number, length: number): bigint;
}

/** Loads the WebAssembly built from web/core. Every call sends JSON and gets JSON back. */
export async function loadCore(wasm: ArrayBuffer): Promise<FitlingCore> {
  const wasi = new WASI([], [], [
    new OpenFile(new File([])),
    ConsoleStdout.lineBuffered((line) => console.log(line)),
    ConsoleStdout.lineBuffered((line) => console.warn(line)),
  ]);
  const { instance } = await WebAssembly.instantiate(wasm, { wasi_snapshot_preview1: wasi.wasiImport });
  wasi.initialize(instance as { exports: { memory: WebAssembly.Memory; _initialize?: () => unknown } });
  const exports = instance.exports as unknown as Exports;

  function call(fn: string, input: unknown): unknown {
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
    localizedText: (input) => call("localizedText", input) as { text: string },
  };
}
