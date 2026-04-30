import { getDownloadURL, ref, uploadBytes } from "firebase/storage";

// Firestore doc limit is 1MB. We store the same URL in 3 fields
// (imageUrl, photoUrls[0], photos[0].url) so max per-field = 150KB
const MAX_INLINE_BYTES = 150_000;

/** FileReader dataURL — always works, never hangs */
const readAsDataUrl = (blob) =>
  new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = () => reject(new Error("Nem sikerult beolvasni a fajlt."));
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
    el.onerror = () => reject(new Error("A kep nem toltheto be tomoriteshez."));
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

  throw new Error("A kep tul nagy. Valassz kisebb kepet (max ~1 MB).");
}

export async function uploadImageWithFallback({ file, storage, folder }) {
  if (!file) throw new Error("Nincs kivalasztott fajl.");

  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, "_");

  // Try Firebase Storage with a hard 5-second timeout.
  // Without this, uploadBytes can hang forever when the bucket is not provisioned.
  try {
    const storageRef = ref(storage, `${folder}/${Date.now()}_${safeName}`);
    const url = await Promise.race([
      uploadBytes(storageRef, file).then((snap) => getDownloadURL(snap.ref)),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("storage-timeout")), 5000),
      ),
    ]);
    return { url, mode: "storage", message: "Kep feltoltve." };
  } catch {
    // Storage not available or timed out — fall through to inline
  }

  const url = await fileToOptimizedDataUrl(file);
  return { url, mode: "inline", message: "Kep beagyazva." };
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
