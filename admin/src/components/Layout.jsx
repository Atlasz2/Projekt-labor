import React, { useEffect, useState } from "react";
import { NavLink, Outlet, useNavigate } from "react-router-dom";
import { onAuthStateChanged } from "firebase/auth";
import { auth } from "../firebaseConfig";
import { resolveUserRole } from "../utils/resolveUserRole";
import "../styles/Layout.css";

function Layout() {
  const navigate = useNavigate();
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [currentUserLabel, setCurrentUserLabel] = useState("Nincs bejelentkezve");
  const [currentRole, setCurrentRole] = useState("user");

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (user) => {
      if (!user) {
        setCurrentUserLabel("Nincs bejelentkezve");
        setCurrentRole("user");
        return;
      }

      const role = await resolveUserRole(user);
      const email = user.email || "ismeretlen";

      setCurrentRole(role);
      setCurrentUserLabel(`${email} (${role})`);
      localStorage.setItem("admin_role", role);
    });

    return () => unsubscribe();
  }, []);

  const handleLogout = () => {
    window.handleDemoLogout();
    navigate("/");
  };

  const renderNavLink = (to, icon, label) => (
    <li>
      <NavLink
        to={to}
        className={({ isActive }) => (isActive ? "nav-link active" : "nav-link")}
      >
        <span className="nav-icon" aria-hidden="true">{icon}</span>
        <span className="nav-label">{label}</span>
      </NavLink>
    </li>
  );

  return (
    <div className="layout">
      <aside className={`sidebar ${sidebarOpen ? "open" : "closed"}`}>
        <div className="sidebar-shell">
          <div className="sidebar-header">
            <div className="header-brand">
              <div className="brand-mark">NV</div>
              <div className="header-content">
                <p className="brand-kicker">Admin</p>
                <h2>Nagyvázsony</h2>
              </div>
            </div>
            <button
              className="sidebar-close-btn"
              onClick={() => setSidebarOpen(false)}
              title="Bezárás"
            >
              ✕
            </button>
          </div>

          <div className="current-user-card">
            <span className="current-user-label">Aktív fiók</span>
            <div className="current-user">{currentUserLabel}</div>
          </div>

          <nav className="sidebar-nav">
            <ul className="nav-links">
              {renderNavLink("/dashboard", "DB", "Dashboard")}

              {currentRole === "admin" && (
                <>
                  <li className="nav-header">Túrák kezelése</li>
                  {renderNavLink("/trips", "TU", "Túrák")}
                  {renderNavLink("/stations", "AL", "Állomások")}

                  <li className="nav-header">Települési tartalom</li>
                  {renderNavLink("/about", "NT", "Nagyvázsony története")}
                  {renderNavLink("/events", "RE", "Rendezvények")}
                  {renderNavLink("/accommodations", "SZ", "Szállások")}
                  {renderNavLink("/restaurants", "VE", "Vendéglátás")}
                  {renderNavLink("/contact", "KA", "Kapcsolat")}
                </>
              )}

              <li className="nav-header">Nézetek</li>
              {renderNavLink("/achievements", "AC", "Achievementek")}
              {renderNavLink("/map", "TE", "Térkép")}
              {renderNavLink("/users", "FU", "Felhasználók")}

              {currentRole === "admin" && (
                <>
                  <li className="nav-header">Rendszer</li>
                  {renderNavLink("/seed-database", "AD", "Adatbázis feltöltés")}
                </>
              )}
            </ul>
          </nav>

          <div className="sidebar-footer">
            <button className="logout-btn" onClick={handleLogout}>
              <span className="logout-icon">KI</span>
              <span className="logout-label">Kijelentkezés</span>
            </button>
          </div>
        </div>
      </aside>

      {!sidebarOpen && (
        <button className="sidebar-open-btn" onClick={() => setSidebarOpen(true)} title="Megnyitás">
          ☰
        </button>
      )}

      <main className={`main-content ${sidebarOpen ? "expanded" : "full"}`}>
        <div className="content-shell">
          <Outlet />
        </div>
      </main>
    </div>
  );
}

export default Layout;
