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
import { useProject } from '../context/ProjectContext';
import { docProjectId } from '../utils/projects';

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
  // White-label: a tartalom az aktív településre (projectId) van szűrve, és az
  // új/szerkesztett elem is oda kerül. A hiányzó projectId az alapértelmezett
  // projektet jelenti (a régi adat is látszik).
  const { activeProjectId } = useProject();
  const key = [collectionName, activeProjectId];
  const invalidate = () =>
    queryClient.invalidateQueries({ queryKey: [collectionName] });

  const query = useQuery({
    queryKey: key,
    queryFn: async () => {
      const snapshot = await getDocs(collection(db, collectionName));
      return snapshot.docs
        .filter((d) => docProjectId(d.data()) === activeProjectId)
        .map(mapper);
    },
  });

  const add = useMutation({
    mutationFn: async (data) => {
      const ref = await addDoc(collection(db, collectionName), {
        ...data,
        projectId: activeProjectId,
      });
      if (options.afterAdd) await options.afterAdd(ref.id, data);
      return ref;
    },
    onSuccess: invalidate,
  });

  const update = useMutation({
    mutationFn: ({ id, data }) =>
      updateDoc(doc(db, collectionName, id), {
        ...data,
        projectId: activeProjectId,
      }),
    onSuccess: invalidate,
  });

  const remove = useMutation({
    mutationFn: (id) => deleteDoc(doc(db, collectionName, id)),
    onSuccess: invalidate,
  });

  return { query, add, update, remove };
}
