import { getDownloadURL, ref, uploadBytes } from "firebase/storage";

// Firestore doc limit is 1MB. We store the same URL in 3 fields
// (imageUrl, photoUrls[0], photos[0].url) so max per-field = 150KB
const MAX_INLINE_BYTES = 150_000;
const STORAGE_TIMEOUT_MS = 30_000;

/** FileReader dataURL — always works, never hangs */
const readAsDataUrl = (blob) =>
  new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = () => reject(new Error("Nem sikerült beolvasni a fájlt."));
    r.readAsDataURL(blob);
  });

/** canvas.toBlob with a hard timeout so it cannot hang forever */
const canvasToBlob = (canvas, type, quality, timeoutMs = 6000) =>
  new Promise((resolve) => {
    const t = setTimeout(() => resolve(null), timeoutMs);
    try {
      canvas.toBlob(
        (blob) => { clearTimeout(t); resolve(blob); },
        type,
        quality,
      );
    } catch {
      clearTimeout(t);
      resolve(null);
    }
  });

export async function fileToOptimizedDataUrl(file) {
  // Step 1: raw FileReader – always works
  const raw = await readAsDataUrl(file);
  if (raw.length <= MAX_INLINE_BYTES) return raw;

  // Step 2: load from that dataURL (more reliable than blob URL via createObjectURL)
  const img = await new Promise((resolve, reject) => {
    const el = new Image();
    el.onload = () => resolve(el);
    el.onerror = () => reject(new Error("A kép nem tölthető be a tömörítéshez."));
    el.src = raw;
  });

  // Step 3: try canvas compression at decreasing quality/size
  for (const [maxDim, quality] of [
    [1200, 0.75],
    [900, 0.65],
    [700, 0.55],
    [500, 0.45],
    [400, 0.35],
  ]) {
    const scale = Math.min(1, maxDim / Math.max(img.width, img.height, 1));
    const w = Math.max(1, Math.round(img.width * scale));
    const h = Math.max(1, Math.round(img.height * scale));

    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d");
    if (!ctx) continue;
    ctx.drawImage(img, 0, 0, w, h);

    const blob = await canvasToBlob(canvas, "image/jpeg", quality);
    if (!blob) continue;

    const dataUrl = await readAsDataUrl(blob);
    if (dataUrl.length <= MAX_INLINE_BYTES) return dataUrl;
  }

  throw new Error("A kép túl nagy. Válassz kisebb képet (legfeljebb kb. 1 MB).");
}

// A feltöltött képek felső határa: a telefon kijelzőjén ennél nagyobb
// felbontás nem látszik, a nagyobb fájl viszont lassítja a betöltést (egy
// tömörítetlen 2 MB-os fotó mobilneten másodpercekig töltődik).
const UPLOAD_MAX_DIM = 1600;
const UPLOAD_JPEG_QUALITY = 0.82;
// Ez alatt a méret alatt nem nyúlunk a fájlhoz (már elég kicsi).
const UPLOAD_SKIP_BYTES = 300_000;
const IMAGE_LOAD_TIMEOUT_MS = 8000;

/** A kép betöltése időkorláttal; hiba vagy időtúllépés esetén null. */
const loadImage = (src) =>
  new Promise((resolve) => {
    const el = new Image();
    const t = setTimeout(() => resolve(null), IMAGE_LOAD_TIMEOUT_MS);
    el.onload = () => { clearTimeout(t); resolve(el); };
    el.onerror = () => { clearTimeout(t); resolve(null); };
    el.src = src;
  });

/**
 * Feltöltés előtti kicsinyítés és tömörítés: a hosszabbik oldal legfeljebb
 * UPLOAD_MAX_DIM pixel, JPEG (a PNG átlátszóság miatt PNG marad). Bármilyen
 * hiba esetén, vagy ha nem lenne kisebb, az eredeti fájl megy fel.
 */
export async function shrinkImageForUpload(file) {
  if (!file?.type?.startsWith("image/")) return file;
  // Az animált GIF és a vektoros SVG vászonra rajzolva elveszítené a lényegét.
  if (file.type === "image/gif" || file.type === "image/svg+xml") return file;
  if (file.size <= UPLOAD_SKIP_BYTES) return file;

  try {
    const img = await loadImage(await readAsDataUrl(file));
    if (!img || !img.width || !img.height) return file;

    const scale = Math.min(1, UPLOAD_MAX_DIM / Math.max(img.width, img.height));
    const w = Math.max(1, Math.round(img.width * scale));
    const h = Math.max(1, Math.round(img.height * scale));
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext("2d");
    if (!ctx) return file;
    ctx.drawImage(img, 0, 0, w, h);

    const type = file.type === "image/png" ? "image/png" : "image/jpeg";
    const blob = await canvasToBlob(canvas, type, UPLOAD_JPEG_QUALITY);
    if (!blob || blob.size >= file.size) return file;

    const ext = type === "image/png" ? ".png" : ".jpg";
    const name = file.name.replace(/\.[^.]*$/, "") + ext;
    return new File([blob], name, { type });
  } catch {
    return file;
  }
}

export async function uploadImageWithFallback({ file: original, storage, folder }) {
  if (!original) throw new Error("Nincs kiválasztott fájl.");

  const file = await shrinkImageForUpload(original);
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, "_");

  // Firebase Storage feltöltés kemény időkorláttal: enélkül az uploadBytes
  // örökre függhet, ha a bucket nincs létrehozva. Nagyobb képeknél lassú
  // mobilneten is legyen idő a feltöltésre, ezért 30 másodperc.
  let timer;
  try {
    const storageRef = ref(storage, `${folder}/${Date.now()}_${safeName}`);
    const url = await Promise.race([
      uploadBytes(storageRef, file).then((snap) => getDownloadURL(snap.ref)),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error("storage-timeout")), STORAGE_TIMEOUT_MS);
      }),
    ]);
    return { url, mode: "storage", message: "Kép feltöltve." };
  } catch {
    // Storage not available or timed out — fall through to inline
  } finally {
    clearTimeout(timer);
  }

  const url = await fileToOptimizedDataUrl(file);
  return {
    url,
    mode: "inline",
    // Figyelmeztetes: a beagyazott (base64) kep a Firestore dokumentumba kerul,
    // ami erosen lassitja a betoltest. Csak vegso menedek.
    message:
      "FIGYELEM: a kép a Storage helyett a dokumentumba ágyazódott (lassítja az alkalmazást). Ellenőrizd a Storage-jogosultságot, és próbáld újra.",
  };
}
export const fetchDataUrl = async (url) => {
  const response = await fetch(url);
  const blob = await response.blob();
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve(reader.result);
    reader.readAsDataURL(blob);
  });
};
