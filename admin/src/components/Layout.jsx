import { Link, Outlet, useNavigate } from 'react-router-dom';
import '../styles/Layout.css';

function Layout() {
  const navigate = useNavigate();

  const handleLogout = () => {
    window.handleDemoLogout();
    navigate('/login');
  };

  return (
    <div className="layout">
      <aside className="sidebar">
        <div className="sidebar-header">
          <h2>Admin Panel</h2>
          <span className="admin-badge">Nagyvázsonyi túra</span>
        </div>
        <nav>
          <ul className="nav-links">
            <li><Link to="/">📊 Dashboard</Link></li>
            <li><Link to="/trips">🚶 Túrák</Link></li>
            <li><Link to="/stations">📍 Állomások</Link></li>
            <li><Link to="/map">🗺️ Térkép</Link></li>
            <li><Link to="/users">👥 Felhasználók</Link></li>
          </ul>
        </nav>
        <button className="logout-btn" onClick={handleLogout}>
          Kijelentkezés
        </button>
      </aside>
      <main className="main-content">
        <Outlet />
      </main>
    </div>
  );
}

export default Layout;
