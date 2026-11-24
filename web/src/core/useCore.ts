import { useEffect, useState } from "react";
import { type FitlingCore, loadCore } from "./fitlingCore";

let loading: Promise<FitlingCore> | undefined;

/**
 * The rules, loaded once: the gzipped WebAssembly (3.8 MB instead of 13), unpacked in the browser. A server
 * that already unpacked it (Content-Encoding) hands over the plain module, which starts with "\0asm".
 */
export function core(): Promise<FitlingCore> {
  loading ??= (async () => {
    const response = await fetch(`${import.meta.env.BASE_URL}fitling-core.wasm.gz`);
    if (!response.ok) throw new Error(`fitling-core: ${response.status}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    const isGzip = bytes[0] === 0x1f && bytes[1] === 0x8b;
    const wasm = isGzip
      ? await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer()
      : bytes.buffer;
    return loadCore(wasm);
  })();
  return loading;
}

/** The rules for a screen: undefined until loaded. */
export function useCore(): FitlingCore | undefined {
  const [loaded, setLoaded] = useState<FitlingCore>();
  useEffect(() => {
    let current = true;
    void core().then((value) => {
      if (current) setLoaded(value);
    });
    return () => {
      current = false;
    };
  }, []);
  return loaded;
}
