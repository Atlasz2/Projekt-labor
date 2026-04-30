import { useState } from 'react';
import { ref, deleteObject } from 'firebase/storage';
import { uploadImageWithFallback } from '../utils/imageUpload';

const MAX_PHOTOS = 6;
const isStorageUrl = (url) =>
  typeof url === 'string' &&
  (url.includes('firebasestorage.googleapis.com') || url.includes('storage.googleapis.com'));

/**
 * Manages photo upload state for a single form.
 * Call commitRemovals() after a successful Firestore save to actually
 * delete the removed files from Firebase Storage.
 * Call reset() or closeEditor() to discard pending removals on cancel.
 */
export function usePhotoManager({ storage, folder }) {
  const [photos,           setPhotos]           = useState([]);
  const [uploading,        setUploading]        = useState(false);
  const [uploadFeedback,   setUploadFeedback]   = useState({ type: 'idle', text: '' });
  const [pendingDeletions, setPendingDeletions] = useState([]);

  const reset = (initial = []) => {
    setPhotos(initial);
    setUploading(false);
    setUploadFeedback({ type: 'idle', text: '' });
    setPendingDeletions([]);
  };

  const upload = async (file) => {
    if (!file) return;
    if (photos.length >= MAX_PHOTOS) {
      setUploadFeedback({ type: 'error', text: 'Maximum 6 kep toltheto fel.' });
      return;
    }
    try {
      setUploadFeedback({ type: 'info', text: `Feltoltes: ${file.name}` });
      setUploading(true);
      const result = await uploadImageWithFallback({ file, storage, folder });
      setPhotos((prev) => [...prev, result.url]);
      setUploadFeedback({ type: 'success', text: result.message });
    } catch (err) {
      setUploadFeedback({ type: 'error', text: err?.message || 'Kep feltoltese sikertelen' });
    } finally {
      setUploading(false);
    }
  };

  const remove = (index) => {
    const url = photos[index];
    setPhotos((prev) => prev.filter((_, i) => i !== index));
    if (isStorageUrl(url)) {
      setPendingDeletions((prev) => [...prev, url]);
    }
  };

  /** Call after a successful Firestore save to prune orphaned Storage files. */
  const commitRemovals = async () => {
    if (pendingDeletions.length === 0) return;
    for (const url of pendingDeletions) {
      try {
        await deleteObject(ref(storage, url));
      } catch {
        // Non-fatal: file may already be deleted or access denied
      }
    }
    setPendingDeletions([]);
  };

  return { photos, uploading, uploadFeedback, upload, remove, reset, commitRemovals };
}
