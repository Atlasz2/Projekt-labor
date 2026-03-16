import { collection, doc, getDoc, getDocs, limit, query, where } from "firebase/firestore";
import { db } from "../firebaseConfig";

export async function resolveUserRole(user) {
  if (!user) return "user";

  try {
    const byUid = await getDoc(doc(db, "users", user.uid));
    if (byUid.exists()) {
      return String(byUid.data().role || "user").toLowerCase();
    }

    const email = (user.email || "").trim().toLowerCase();
    if (!email) return "user";

    const byEmailDoc = await getDoc(doc(db, "users", email));
    if (byEmailDoc.exists()) {
      return String(byEmailDoc.data().role || "user").toLowerCase();
    }

    const byEmailQuery = query(collection(db, "users"), where("email", "==", email), limit(1));
    const byEmailSnapshot = await getDocs(byEmailQuery);
    if (!byEmailSnapshot.empty) {
      return String(byEmailSnapshot.docs[0].data().role || "user").toLowerCase();
    }
  } catch (err) {
    console.error("Szerepkör feloldás hiba:", err);
  }

  return "user";
}
