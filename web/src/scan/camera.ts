/** The codes on food packages: EAN-13, EAN-8 and UPC (ScanSheet on iOS looks for the same). */
const formats = ["ean_13", "ean_8", "upc_a", "upc_e"];

interface Detector {
  detect(source: HTMLVideoElement): Promise<{ rawValue: string }[]>;
}

declare global {
  interface Window {
    BarcodeDetector?: new (options: { formats: string[] }) => Detector;
  }
}

/**
 * Reads barcodes from the back camera into `video` until stopped, and reports each code it reads. The browser's own
 * BarcodeDetector where there is one (Chrome on Android); elsewhere, Safari on the iPhone among them, ZXing.
 * Throws when there is no camera or no permission; the code can then be typed.
 */
export async function startScanning(video: HTMLVideoElement, onCode: (code: string) => void): Promise<() => void> {
  if (!navigator.mediaDevices?.getUserMedia) throw new Error("scan.unavailable");
  const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" }, audio: false });
  video.srcObject = stream;
  video.setAttribute("playsinline", "");
  await video.play();
  let stopped = false;
  const stopStream = () => stream.getTracks().forEach((track) => track.stop());

  if (window.BarcodeDetector) {
    const detector = new window.BarcodeDetector({ formats });
    const look = async () => {
      if (stopped) return;
      try {
        for (const code of await detector.detect(video)) onCode(code.rawValue);
      } catch {
        // A frame that cannot be read yet; the next one may.
      }
      setTimeout(() => void look(), 200);
    };
    void look();
    return () => {
      stopped = true;
      stopStream();
    };
  }

  const { BrowserMultiFormatReader } = await import("@zxing/browser");
  const { BarcodeFormat, DecodeHintType } = await import("@zxing/library");
  const hints = new Map([[DecodeHintType.POSSIBLE_FORMATS, [BarcodeFormat.EAN_13, BarcodeFormat.EAN_8, BarcodeFormat.UPC_A, BarcodeFormat.UPC_E]]]);
  const reader = new BrowserMultiFormatReader(hints);
  const controls = await reader.decodeFromStream(stream, video, (result) => {
    if (result && !stopped) onCode(result.getText());
  });
  return () => {
    stopped = true;
    controls.stop();
    stopStream();
  };
}
