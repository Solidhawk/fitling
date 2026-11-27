import { expect, test } from "vitest";
import { unpack } from "./fitlingCore";

// fitling_call answers the place and the length of its answer in one i64, place in the upper half. A place from 2 GB
// on sets the sign bit, and still has to be read as the place it is (UNFORGET S36).
test("anAnswerFrom2GBOnIsReadWhereItIs", () => {
  expect(unpack((1024n << 32n) | 17n)).toEqual({ pointer: 1024, length: 17 });
  const high = (0x8000_0010n << 32n) | 5n;
  expect(unpack(BigInt.asIntN(64, high))).toEqual({ pointer: 0x8000_0010, length: 5 });
});
