import { Plus } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { addPhoto, listPhotos, type Photo, removePhoto } from "../data/photos";
import { today } from "../day";
import { language, t } from "../i18n";
import { ActionSheet } from "../ui/ActionSheet";
import { Alert } from "../ui/Alert";
import { useDialogFocus } from "../ui/dialogFocus";
import { NavBar } from "../ui/NavBar";

/** A picked image as a JPEG at 85 %, as the app stores it; nil when the browser cannot read the file. */
async function jpeg(file: File): Promise<Blob | undefined> {
  try {
    const bitmap = await createImageBitmap(file);
    const canvas = document.createElement("canvas");
    canvas.width = bitmap.width;
    canvas.height = bitmap.height;
    canvas.getContext("2d")?.drawImage(bitmap, 0, 0);
    bitmap.close();
    return await new Promise<Blob | undefined>((resolve) => canvas.toBlob((blob) => resolve(blob ?? undefined), "image/jpeg", 0.85));
  } catch {
    return undefined;
  }
}

function dayText(day: string, options: Intl.DateTimeFormatOptions): string {
  return new Intl.DateTimeFormat(language(), options).format(new Date(`${day}T12:00:00`));
}

/** A photo as an object URL for as long as it is shown. */
function useImage(image: Blob): string {
  const [url] = useState(() => URL.createObjectURL(image));
  useEffect(() => () => URL.revokeObjectURL(url), [url]);
  return url;
}

function PhotoTile({ photo, onOpen }: { photo: Photo; onOpen: () => void }) {
  const url = useImage(photo.image);
  return (
    <button type="button" className="photo-tile" aria-label={dayText(photo.takenOn, { day: "numeric", month: "long", year: "numeric" })} data-testid="photos.tile" onClick={onOpen}>
      <img src={url} alt="" />
      <span className="photo-date" aria-hidden="true">
        {dayText(photo.takenOn, { day: "numeric", month: "short" })}
      </span>
    </button>
  );
}

function PhotoDetail({ photo, onClose, onDelete }: { photo: Photo; onClose: () => void; onDelete: () => void }) {
  const url = useImage(photo.image);
  const sheet = useRef<HTMLDivElement>(null);
  const [confirming, setConfirming] = useState(false);
  const title = dayText(photo.takenOn, { day: "numeric", month: "long", year: "numeric" });
  useDialogFocus(sheet, onClose);
  return (
    <div ref={sheet} className="sheet photo-detail" role="dialog" aria-modal="true" aria-label={title} tabIndex={-1}>
      <NavBar
        title={title}
        leading={
          <button type="button" className="nav-back nav-action" onClick={onClose}>
            {t("common.ok")}
          </button>
        }
        trailing={
          <button type="button" className="nav-back nav-action destructive" onClick={() => setConfirming(true)}>
            {t("photos.delete")}
          </button>
        }
      />
      <img className="photo-large" src={url} alt="" />
      {confirming && (
        <ActionSheet
          title={t("photos.delete.title")}
          actions={[
            {
              label: t("photos.delete"),
              destructive: true,
              onSelect: () => {
                setConfirming(false);
                onDelete();
              },
            },
          ]}
          onCancel={() => setConfirming(false)}
        />
      )}
    </div>
  );
}

/**
 * Progress photos (ProgressPhotosView on iOS): only in this browser, never uploaded; signing out removes them. Added
 * from the photo library or the camera, shown in a grid with their date, newest first.
 */
export function Photos({ onBack }: { onBack: () => void }) {
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [opened, setOpened] = useState<Photo>();
  const [failed, setFailed] = useState(false);
  const picker = useRef<HTMLInputElement>(null);

  const reload = useCallback(async () => {
    try {
      setPhotos(await listPhotos());
    } catch {
      setFailed(true);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  async function add(file: File | undefined) {
    if (!file) return;
    const image = await jpeg(file);
    try {
      if (!image) throw new Error("photos.failed");
      await addPhoto(image, today());
    } catch {
      setFailed(true);
    }
    await reload();
  }

  return (
    <div className="tab-page pushed" data-page="photos">
      <NavBar title={t("photos.title")} back={t("training.title")} onBack={onBack} large />
      <div className="photos">
        <p className="footnote secondary">{t("photos.privacy")}</p>
        <button type="button" className="button button-secondary photos-add" onClick={() => picker.current?.click()}>
          <Plus aria-hidden="true" size={18} strokeWidth={2.4} />
          <span>{t("photos.add")}</span>
        </button>
        <input
          ref={picker}
          className="visually-hidden"
          type="file"
          accept="image/*"
          tabIndex={-1}
          aria-hidden="true"
          data-testid="photos.picker"
          onChange={(event) => {
            void add(event.target.files?.[0]);
            event.target.value = "";
          }}
        />
        {photos.length === 0 && <p className="list-footer">{t("photos.empty")}</p>}
        <div className="photo-grid">
          {photos.map((photo) => (
            <PhotoTile key={photo.id} photo={photo} onOpen={() => setOpened(photo)} />
          ))}
        </div>
      </div>
      {opened && (
        <PhotoDetail
          photo={opened}
          onClose={() => setOpened(undefined)}
          onDelete={() => {
            const id = opened.id;
            setOpened(undefined);
            void removePhoto(id).then(reload);
          }}
        />
      )}
      {failed && <Alert title={t("photos.failed")} onClose={() => setFailed(false)} />}
    </div>
  );
}
