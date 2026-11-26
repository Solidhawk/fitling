import { useEffect, useState } from "react";
import { type FitlingCore, loadCore } from "./fitlingCore";

let loading: Promise<FitlingCore> | undefined;

/**
 * The rules, loaded once: the gzipped WebAssembly (3.8 MB instead of 13), unpacked in the browser. A server
 * that already unpacked it (Content-Encoding) hands over the plain module, which starts with "\0asm".
 */
export function core(): Promise<FitlingCore> {
  loading ??= (async () => {
    // The rules of this build: their version in the address, the copy the service worker keeps for it.
    const response = await fetch(`${import.meta.env.BASE_URL}fitling-core.wasm.gz?v=${__CORE_VERSION__}`);
    if (!response.ok) throw new Error(`fitling-core: ${response.status}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    const isGzip = bytes[0] === 0x1f && bytes[1] === 0x8b;
    const wasm = isGzip
      ? await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer()
      : bytes.buffer;
    return loadCore(wasm);
  })().catch((error: unknown) => {
    // Not kept: the next call downloads again.
    loading = undefined;
    throw error;
  });
  return loading;
}

/** The rules for a screen: undefined until loaded. */
export function useCore(): FitlingCore | undefined {
  const [loaded, setLoaded] = useState<FitlingCore>();
  useEffect(() => {
    let current = true;
    // A failure is shown by the app (useCoreFailure); the screen keeps waiting.
    core().then(
      (value) => current && setLoaded(value),
      () => undefined,
    );
    return () => {
      current = false;
    };
  }, []);
  return loaded;
}

/**
 * Whether the rules could not be downloaded (a weak connection, a browser without DecompressionStream), and a way to
 * try again. The app then shows "no connection" instead of a screen that waits for ever.
 */
export function useCoreFailure(active: boolean): { failed: boolean; retry: () => void } {
  const [failed, setFailed] = useState(false);
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    if (!active) return;
    let current = true;
    core().then(
      () => current && setFailed(false),
      () => current && setFailed(true),
    );
    return () => {
      current = false;
    };
  }, [active, attempt]);
  return { failed, retry: () => setAttempt((count) => count + 1) };
}
