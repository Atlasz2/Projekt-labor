import { safeString } from './safeString';

/**
 * Normalizes the photo array from a Firestore document.
 * Handles all three legacy storage shapes: photos[{url}], photoUrls[], imageUrl.
 */
export const normalizePhotosFromDoc = (docData) => {
  const fromPhotos = Array.isArray(docData.photos)
    ? docData.photos.map((p) => (typeof p === 'string' ? p : p?.url)).filter(Boolean)
    : [];
  const fromPhotoUrls = Array.isArray(docData.photoUrls)
    ? docData.photoUrls.filter(Boolean)
    : [];
  const fromUrl = safeString(docData.imageUrl);
  return [
    ...new Set([...fromPhotos, ...fromPhotoUrls, ...(fromUrl ? [fromUrl] : [])]),
  ].slice(0, 6);
};

/**
 * Builds the three image fields written to Firestore for cross-client compatibility.
 * photos[{url}] for older mobile readers, photoUrls[] for newer, imageUrl for cover.
 */
export const buildPhotoFields = (photos) => {
  const urls = Array.isArray(photos) ? photos.filter(Boolean) : [];
  if (!urls.length) return { imageUrl: '', photoUrls: [], photos: [] };
  return {
    imageUrl: urls[0],
    photoUrls: urls,
    photos: urls.map((url) => ({ url })),
  };
};
