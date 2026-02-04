import React, { useState, useEffect } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAppStore } from '../store/appStore';
import { AuthService } from '../services/authService';
import { AuthModal } from './AuthModal';
import '../styles/Header.css';
import { Toast } from '../components/Toast';

export const Header = () => {
  const { user, setUser } = useAppStore();
  const [showAuthModal, setShowAuthModal] = useState(false);
  const [showMobileMenu, setShowMobileMenu] = useState(false);
  const [toast, setToast] = useState(null);
  const navigate = useNavigate();

  useEffect(() => {
    const unsubscribe = AuthService.getCurrentUser((currentUser) => {
      setUser(currentUser);
    });
    return unsubscribe;
  }, [setUser]);

  const handleLogout = async () => {
    try {
      await AuthService.logout();
      setUser(null);
      setShowMobileMenu(false);
      setToast({ type: 'success', message: 'Sikeresen kijelentkeztél!' });
      setTimeout(() => {
        navigate('/'); // Vissza a login oldalra
      }, 800);
    } catch (error) {
      console.error('Kijelentkezési hiba:', error);
      setToast({ type: 'error', message: 'Hiba a kijelentkezés során' });
    }
  };

  return (
    <>
      <header className="header">
        <Link to={user ? "/admin" : "/"} className="logo">
          🏔️ Túraútvonal Felfedező
        </Link>

        <nav className={`nav ${showMobileMenu ? 'active' : ''}`}>
          {user && (
            <>
              <Link to="/home" onClick={() => setShowMobileMenu(false)}>
                🏠 Kezdőoldal
              </Link>
              {user?.isAdmin && (
                <Link to="/admin" onClick={() => setShowMobileMenu(false)}>
                  ⚙️ Admin
                </Link>
              )}
            </>
          )}

          {user ? (
            <div className="user-menu">
              <div className="user-info">
                <span className="user-avatar">👤</span>
                <div className="user-details">
                  <span className="user-name">{user.displayName || user.email}</span>
                  <span className="user-email">{user.email}</span>
                </div>
              </div>
              <button onClick={handleLogout} className="logout-btn">
                🚪 Kijelentkezés
              </button>
            </div>
          ) : null}
        </nav>

        {user && (
          <button
            className={`hamburger ${showMobileMenu ? 'active' : ''}`}
            onClick={() => setShowMobileMenu(!showMobileMenu)}
          >
            <span></span>
            <span></span>
            <span></span>
          </button>
        )}
      </header>

      {showMobileMenu && (
        <div
          className="nav-overlay"
          onClick={() => setShowMobileMenu(false)}
        ></div>
      )}

      {toast && (
        <Toast
          type={toast.type}
          message={toast.message}
          onClose={() => setToast(null)}
        />
      )}
    </>
  );
};
