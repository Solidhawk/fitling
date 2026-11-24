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
  isValid: boolean;
}

export type Sex = DailyPlanInput["sex"];
export type Goal = DailyPlanInput["goal"];

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
    const result = JSON.parse(answer) as { error?: string };
    if (typeof result.error === "string") throw new Error(result.error);
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
  };
}
