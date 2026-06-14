import React, { useState } from 'react';
import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAdminAuth } from '../context/AdminAuthContext';
import '../styles/Layout.css';

function Layout() {
  const navigate = useNavigate();
  const { userEmail, userRole, logout } = useAdminAuth();
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [darkMode, setDarkMode] = useState(
    () => document.documentElement.classList.contains('dark')
  );

  const toggleTheme = () => {
    const next = !darkMode;
    setDarkMode(next);
    document.documentElement.classList.toggle('dark', next);
    localStorage.setItem('adminDarkMode', String(next));
  };

  const userInitial = (userEmail || '?').charAt(0).toUpperCase();

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
                <h2>Nagyvázsony</h2>
              </div>
            </div>
            <button
              className="sidebar-close-btn"
              onClick={() => setSidebarOpen(false)}
              title="Bezárás"
            >
              x
            </button>
          </div>

          <div className="current-user-card">
            <div className="current-user-avatar" aria-hidden="true">
              {userInitial}
            </div>
            <div className="current-user-info">
              <span className="current-user-email" title={userEmail || ''}>
                {userEmail || 'Nincs bejelentkezve'}
              </span>
              <span className={`role-pill role-${userRole}`}>{userRole}</span>
            </div>
          </div>

          <nav className="sidebar-nav">
            <ul className="nav-links">
              {renderNavLink('/dashboard', 'DB', 'Vezérlőpult')}

              {userRole === 'admin' && (
                <>
                  <li className="nav-header">Túrák kezelése</li>
                  {renderNavLink('/trips',    'TÚ', 'Túrák')}
                  {renderNavLink('/stations', 'ÁL', 'Állomások')}

                  <li className="nav-header">Települési tartalom</li>
                  {renderNavLink('/about',          'NT', 'Nagyvázsony története')}
                  {renderNavLink('/events',          'RE', 'Rendezvények')}
                  {renderNavLink('/accommodations',  'SZ', 'Szállások')}
                  {renderNavLink('/restaurants',     'VE', 'Vendéglátóhelyek')}
                  {renderNavLink('/contact',         'KA', 'Kapcsolat')}
                </>
              )}

              <li className="nav-header">Nézetek</li>
              {renderNavLink('/achievements', 'JU', 'Jutalmak')}
              {renderNavLink('/bug-reports',  'HB', 'Hibajelentések')}
              {renderNavLink('/map',          'TÉ', 'Térkép')}
              {renderNavLink('/users',        'FE', 'Felhasználók')}

              {userRole === 'admin' && (
                <>
                  <li className="nav-header">Rendszer</li>
                  {renderNavLink('/seed-database', 'AD', 'Adatbázis kezelése')}
                </>
              )}
            </ul>
          </nav>

          <div className="sidebar-footer">
            <button
              className="theme-toggle-btn"
              onClick={toggleTheme}
              title={darkMode ? 'Világos mód' : 'Sötét mód'}
            >
              <span className="theme-toggle-icon" aria-hidden="true">
                {darkMode ? '☀' : '☾'}
              </span>
              <span className="theme-toggle-label">
                {darkMode ? 'Világos mód' : 'Sötét mód'}
              </span>
            </button>
            <button className="logout-btn" onClick={handleLogout}>
              <span className="logout-icon">KI</span>
              <span className="logout-label">Kijelentkezés</span>
            </button>
          </div>
        </div>
      </aside>

      {!sidebarOpen && (
        <button
          className="sidebar-open-btn"
          onClick={() => setSidebarOpen(true)}
          title="Megnyitás"
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
