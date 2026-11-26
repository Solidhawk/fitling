import { afterEach, expect, test, vi } from "vitest";
import { startScanning } from "./camera";

afterEach(() => vi.unstubAllGlobals());

// When starting fails after the camera came on (playing is refused, the reader does not load), the camera goes off.
test("aFailedStartTurnsTheCameraOff", async () => {
  const stop = vi.fn();
  vi.stubGlobal("navigator", { mediaDevices: { getUserMedia: async () => ({ getTracks: () => [{ stop }] }) } });
  const video = { srcObject: null, setAttribute: () => undefined, play: () => Promise.reject(new Error("AbortError")) } as unknown as HTMLVideoElement;
  await expect(startScanning(video, () => undefined)).rejects.toThrow("AbortError");
  expect(stop).toHaveBeenCalled();
});
