import PropTypes from "prop-types";
import { createContext, useContext, useEffect, useState } from "react";
import { onAuthStateChanged, signOut } from "firebase/auth";
import { auth } from "../firebaseConfig";
import { resolveUserRole } from "../utils/resolveUserRole";

const AdminAuthContext = createContext(null);

export function AdminAuthProvider({ children }) {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [userRole, setUserRole] = useState("user");
  const [userEmail, setUserEmail] = useState("");
  const [userUid, setUserUid] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (user) => {
      if (!user) {
        setIsLoggedIn(false);
        setUserRole("user");
        setUserEmail("");
        setUserUid("");
        setLoading(false);
        return;
      }

      const role = await resolveUserRole(user);
      // A 'developer' az admin fölötti szint (több település kezelése), ezért
      // ugyanúgy beléphet, mint az admin.
      if (role !== "admin" && role !== "developer") {
        sessionStorage.setItem("admin_access_error", "Ehhez a fiókhoz nincs admin jogosultság.");
        await signOut(auth);
        setIsLoggedIn(false);
        setUserRole("user");
        setUserEmail("");
        setUserUid("");
        setLoading(false);
        return;
      }

      setIsLoggedIn(true);
      setUserRole(role);
      setUserEmail(user.email || "");
      setUserUid(user.uid);
      setLoading(false);
    });

    return unsubscribe;
  }, []);

  const logout = () => {
    sessionStorage.removeItem("admin_access_error");
    return signOut(auth);
  };

  return (
    <AdminAuthContext.Provider value={{ isLoggedIn, userRole, userEmail, userUid, loading, logout }}>
      {children}
    </AdminAuthContext.Provider>
  );
}

AdminAuthProvider.propTypes = {
  children: PropTypes.node.isRequired,
};

export const useAdminAuth = () => {
  const context = useContext(AdminAuthContext);
  if (context === null) {
    throw new Error("useAdminAuth must be used within AdminAuthProvider");
  }
  return context;
};
