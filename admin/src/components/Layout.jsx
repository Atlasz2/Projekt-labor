import React, { useEffect, useState } from "react";
import { Link, Outlet, useNavigate } from "react-router-dom";
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

  return (
    <div className="layout">
      <aside className={`sidebar ${sidebarOpen ? "open" : "closed"}`}>
        <div className="sidebar-header">
          <div className="header-content">
            <h2>Admin</h2>
            <span className="admin-badge">Nagyvázsonyi</span>
            <div className="current-user">{currentUserLabel}</div>
          </div>
          <button className="sidebar-close-btn" onClick={() => setSidebarOpen(false)} title="Bezárás">✕</button>
        </div>

        <nav>
          <ul className="nav-links">
            <li>
              <Link to="/dashboard"><span className="nav-icon">📊</span><span className="nav-label">Dashboard</span></Link>
            </li>

            {currentRole === "admin" && (
              <>
                <li className="nav-header">Túrák menedzsment</li>
                <li><Link to="/trips"><span className="nav-icon">🚶</span><span className="nav-label">Túrák</span></Link></li>
                <li><Link to="/stations"><span className="nav-icon">📍</span><span className="nav-label">Állomások</span></Link></li>

                <li className="nav-header">Város információ</li>
                <li><Link to="/about"><span className="nav-icon">🏛️</span><span className="nav-label">Nagyvázsony története</span></Link></li>
                <li><Link to="/events"><span className="nav-icon">🎉</span><span className="nav-label">Rendezvények</span></Link></li>
                <li><Link to="/accommodations"><span className="nav-icon">🏨</span><span className="nav-label">Szállások</span></Link></li>
                <li><Link to="/restaurants"><span className="nav-icon">🍽️</span><span className="nav-label">Vendéglátás</span></Link></li>
                <li><Link to="/contact"><span className="nav-icon">📞</span><span className="nav-label">Kapcsolat</span></Link></li>
              </>
            )}

            <li className="nav-header">Nézetek</li>
            <li><Link to='/achievements'><span className='nav-icon'>🏆</span><span className='nav-label'>Achievementek</span></Link></li>
            <li><Link to="/map"><span className="nav-icon">🗺️</span><span className="nav-label">Térkép</span></Link></li>
            <li><Link to="/users"><span className="nav-icon">👥</span><span className="nav-label">Felhasználók</span></Link></li>

            {currentRole === "admin" && (
              <>
                <li className="nav-header">Rendszer</li>
                <li><Link to="/seed-database"><span className="nav-icon">🗄️</span><span className="nav-label">Adatbázis Feltöltés</span></Link></li>
              </>
            )}
          </ul>
        </nav>

        <button className="logout-btn" onClick={handleLogout}>
          <span className="logout-icon">🚪</span>
          <span className="logout-label">Kijelentkezés</span>
        </button>
      </aside>

      {!sidebarOpen && (
        <button className="sidebar-open-btn" onClick={() => setSidebarOpen(true)} title="Megnyitás">☰</button>
      )}

      <main className={`main-content ${sidebarOpen ? "expanded" : "full"}`}>
        <Outlet />
      </main>
    </div>
  );
}

export default Layout;


