import { useEffect, useRef, useState } from "react";
import { t } from "../i18n";
import { startScanning } from "../scan/camera";
import { SecondaryButton } from "../ui/Buttons";
import { useDialogFocus } from "../ui/dialogFocus";
import { NavBar } from "../ui/NavBar";

/**
 * The camera looks for EAN-13, EAN-8 and UPC barcodes. Where scanning is not possible (no camera, no permission), the
 * barcode can be typed in (ScanSheet.swift). A misread does nothing: the camera keeps looking.
 */
export function Scan({ onCode, onCancel }: { onCode: (code: string) => void; onCancel: () => void }) {
  const video = useRef<HTMLVideoElement>(null);
  const sheet = useRef<HTMLDivElement>(null);
  const [canScan, setCanScan] = useState(true);
  const [typed, setTyped] = useState("");
  const latest = useRef(onCode);
  latest.current = onCode;
  useDialogFocus(sheet, onCancel);

  useEffect(() => {
    if (!video.current) return;
    let stop: (() => void) | undefined;
    let closed = false;
    startScanning(video.current, (code) => latest.current(code)).then(
      (stopper) => (closed ? stopper() : (stop = stopper)),
      () => setCanScan(false),
    );
    return () => {
      closed = true;
      stop?.();
    };
  }, []);

  return (
    <div ref={sheet} className="sheet" role="dialog" aria-modal="true" aria-label={t("scan.title")} tabIndex={-1} data-screen="scan">
      <NavBar
        title={t("scan.title")}
        leading={
          <button type="button" className="nav-back nav-action" onClick={onCancel}>
            {t("common.cancel")}
          </button>
        }
      />
      <div className="scan stack-l">
        {canScan ? (
          <video ref={video} className="scan-camera" muted playsInline aria-label={t("scan.title")} />
        ) : (
          <p>{t("scan.unavailable")}</p>
        )}
        <form
          className="scan-manual"
          onSubmit={(event) => {
            event.preventDefault();
            if (typed !== "") onCode(typed);
          }}
        >
          <input
            className="text-field scan-field"
            inputMode="numeric"
            placeholder={t("scan.manual.field")}
            aria-label={t("scan.manual.field")}
            data-testid="scan.manual"
            value={typed}
            onChange={(event) => setTyped(event.target.value)}
          />
          <SecondaryButton type="submit" disabled={typed === ""} data-testid="scan.manual.submit">
            {t("scan.manual.submit")}
          </SecondaryButton>
        </form>
      </div>
    </div>
  );
}
