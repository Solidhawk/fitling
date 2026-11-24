import type { IsoDay } from "../core/fitlingCore";

// Progress photos (TASKS 4.9, ProgressPhotoStore on iOS): only in this browser, in IndexedDB, never uploaded.
// Signing out removes them all: they belong to the account that took them.

export interface Photo {
  id: string;
  takenOn: IsoDay;
  image: Blob;
}

const database = "fitling-photos";
const store = "photos";

function open(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(database, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(store, { keyPath: "id" });
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function run<T>(mode: IDBTransactionMode, work: (photos: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await open();
  try {
    return await new Promise<T>((resolve, reject) => {
      const transaction = db.transaction(store, mode);
      const request = work(transaction.objectStore(store));
      transaction.oncomplete = () => resolve(request.result);
      transaction.onerror = () => reject(transaction.error);
      transaction.onabort = () => reject(transaction.error);
    });
  } finally {
    db.close();
  }
}

/** As stored: the bytes, not a Blob, which not every WebKit keeps in IndexedDB. */
interface StoredPhoto {
  id: string;
  takenOn: IsoDay;
  bytes: ArrayBuffer;
  type: string;
}

/** Newest first. */
export async function listPhotos(): Promise<Photo[]> {
  const all = await run<StoredPhoto[]>("readonly", (photos) => photos.getAll() as IDBRequest<StoredPhoto[]>);
  return all
    .sort((a, b) => (a.takenOn === b.takenOn ? 0 : a.takenOn < b.takenOn ? 1 : -1))
    .map((stored) => ({ id: stored.id, takenOn: stored.takenOn, image: new Blob([stored.bytes], { type: stored.type }) }));
}

export async function addPhoto(image: Blob, takenOn: IsoDay): Promise<Photo> {
  const stored: StoredPhoto = { id: crypto.randomUUID(), takenOn, bytes: await image.arrayBuffer(), type: image.type };
  await run("readwrite", (photos) => photos.put(stored));
  return { id: stored.id, takenOn, image };
}

export async function removePhoto(id: string): Promise<void> {
  await run("readwrite", (photos) => photos.delete(id));
}

/** On signing out and when the account is deleted. */
export async function removeAllPhotos(): Promise<void> {
  await new Promise<void>((resolve) => {
    const request = indexedDB.deleteDatabase(database);
    // A blocked delete finishes once open tabs close; signing out does not wait for that.
    request.onsuccess = request.onerror = request.onblocked = () => resolve();
  });
}
