import React, { useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAdminAuth } from '../context/AdminAuthContext';
import '../styles/Layout.css';

function Layout() {
  const navigate = useNavigate();
  const { userEmail, userRole, logout } = useAdminAuth();
  const [sidebarOpen, setSidebarOpen] = useState(true);

  const handleLogout = async () => {
    await logout();
    navigate('/');
  };

  const renderNavLink = (to, icon, label) => (
    <li>
      <NavLink
        to={to}
        className={({ isActive }) => (isActive ? 'nav-link active' : 'nav-link')}
      >
        <span className="nav-icon" aria-hidden="true">{icon}</span>
        <span className="nav-label">{label}</span>
      </NavLink>
    </li>
  );

  return (
    <div className="layout">
      <aside className={`sidebar ${sidebarOpen ? 'open' : 'closed'}`}>
        <div className="sidebar-shell">
          <div className="sidebar-header">
            <div className="header-brand">
              <div className="brand-mark">NV</div>
              <div className="header-content">
                <p className="brand-kicker">Admin</p>
                <h2>Nagyvazsony</h2>
              </div>
            </div>
            <button
              className="sidebar-close-btn"
              onClick={() => setSidebarOpen(false)}
              title="Bezaras"
            >
              x
            </button>
          </div>

          <div className="current-user-card">
            <span className="current-user-label">Aktiv fiok</span>
            <div className="current-user">
              {userEmail || 'Nincs bejelentkezve'} ({userRole})
            </div>
          </div>

          <nav className="sidebar-nav">
            <ul className="nav-links">
              {renderNavLink('/dashboard', 'DB', 'Dashboard')}

              {userRole === 'admin' && (
                <>
                  <li className="nav-header">Turak kezelese</li>
                  {renderNavLink('/trips',    'TU', 'Turak')}
                  {renderNavLink('/stations', 'AL', 'Allomosok')}

                  <li className="nav-header">Települesi tartalom</li>
                  {renderNavLink('/about',          'NT', 'Nagyvazsony tortenete')}
                  {renderNavLink('/events',          'RE', 'Rendezvenyek')}
                  {renderNavLink('/accommodations',  'SZ', 'Szallasok')}
                  {renderNavLink('/restaurants',     'VE', 'Vendeglatohelyek')}
                  {renderNavLink('/contact',         'KA', 'Kapcsolat')}
                </>
              )}

              <li className="nav-header">Nezetek</li>
              {renderNavLink('/achievements', 'AC', 'Achievementek')}
              {renderNavLink('/bug-reports',  'HB', 'Hibajelentesek')}
              {renderNavLink('/map',          'TE', 'Terkep')}
              {renderNavLink('/users',        'FU', 'Felhasznalok')}

              {userRole === 'admin' && (
                <>
                  <li className="nav-header">Rendszer</li>
                  {renderNavLink('/seed-database', 'AD', 'Adatbazis feltoltes')}
                </>
              )}
            </ul>
          </nav>

          <div className="sidebar-footer">
            <button className="logout-btn" onClick={handleLogout}>
              <span className="logout-icon">KI</span>
              <span className="logout-label">Kijelentkezes</span>
            </button>
          </div>
        </div>
      </aside>

      {!sidebarOpen && (
        <button
          className="sidebar-open-btn"
          onClick={() => setSidebarOpen(true)}
          title="Megnyitas"
        >
          [=]
        </button>
      )}

      <main className={`main-content ${sidebarOpen ? 'expanded' : 'full'}`}>
        <div className="content-shell">
          <Outlet />
        </div>
      </main>
    </div>
  );
}

export default Layout;
