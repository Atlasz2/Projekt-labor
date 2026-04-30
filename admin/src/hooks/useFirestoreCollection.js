import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  collection,
  getDocs,
  addDoc,
  updateDoc,
  deleteDoc,
  doc,
} from 'firebase/firestore';
import { db } from '../firebaseConfig';

/**
 * Generic CRUD hook for a Firestore collection.
 *
 * @param {string} collectionName  - Firestore collection name
 * @param {(docSnap) => object} mapper - maps a QueryDocumentSnapshot to a plain object
 * @param {object} [options]
 * @param {(id: string, data: object) => Promise<void>} [options.afterAdd]
 *   - optional async callback called after addDoc, receives (newId, submittedData)
 */
export function useFirestoreCollection(collectionName, mapper, options = {}) {
  const queryClient = useQueryClient();
  const key = [collectionName];
  const invalidate = () => queryClient.invalidateQueries({ queryKey: key });

  const query = useQuery({
    queryKey: key,
    queryFn: async () => {
      const snapshot = await getDocs(collection(db, collectionName));
      return snapshot.docs.map(mapper);
    },
  });

  const add = useMutation({
    mutationFn: async (data) => {
      const ref = await addDoc(collection(db, collectionName), data);
      if (options.afterAdd) await options.afterAdd(ref.id, data);
      return ref;
    },
    onSuccess: invalidate,
  });

  const update = useMutation({
    mutationFn: ({ id, data }) => updateDoc(doc(db, collectionName, id), data),
    onSuccess: invalidate,
  });

  const remove = useMutation({
    mutationFn: (id) => deleteDoc(doc(db, collectionName, id)),
    onSuccess: invalidate,
  });

  return { query, add, update, remove };
}
