import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { AuthService } from '../services/authService';
import { useAppStore } from '../store/appStore';
import { Toast } from '../components/Toast';
import '../styles/LoginPage.css';

export default function LoginPage() {
  const navigate = useNavigate();
  const { user, setUser } = useAppStore();
  const [mode, setMode] = useState('login'); // login | signup
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [loading, setLoading] = useState(false);
  const [toast, setToast] = useState(null);

  useEffect(() => {
    // Folyamatos figyelés a user state-re
    const unsubscribe = AuthService.getCurrentUser((currentUser) => {
      if (currentUser) {
        console.log('User bejelentkezett:', currentUser);
        setUser(currentUser);
        navigate('/admin');
      }
    });

    return unsubscribe;
  }, [setUser, navigate]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setToast(null);

    try {
      let loggedInUser;
      
      if (mode === 'signup') {
        loggedInUser = await AuthService.signup(email, password, displayName);
        setToast({ type: 'success', message: 'Sikeres regisztráció!' });
      } else {
        loggedInUser = await AuthService.login(email, password);
        setToast({ type: 'success', message: 'Sikeres bejelentkezés!' });
      }
      
      // Manuálisan frissítjük a user state-t
      if (loggedInUser) {
        console.log('Bejelentkezett user:', loggedInUser);
        setUser({
          uid: loggedInUser.uid,
          email: loggedInUser.email,
          displayName: loggedInUser.displayName || displayName
        });
        
        // Kis delay után navigálunk
        setTimeout(() => {
          navigate('/admin');
        }, 500);
      }
      
    } catch (error) {
      console.error('Auth hiba:', error);
      const errorMessage = error.code === 'auth/invalid-credential' 
        ? 'Hibás e-mail vagy jelszó'
        : error.code === 'auth/user-not-found'
        ? 'Nem létezik ilyen felhasználó'
        : error.code === 'auth/wrong-password'
        ? 'Hibás jelszó'
        : error.code === 'auth/email-already-in-use'
        ? 'Ez az e-mail cím már regisztrálva van'
        : 'Hiba a bejelentkezés során';
      
      setToast({ 
        type: 'error', 
        message: errorMessage
      });
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-page">
      <div className="login-container">
        <div className="login-header">
          <h1>🏰 Nagyvázsony Admin</h1>
          <p>Túraútvonal és program kezelő rendszer</p>
        </div>

        <div className="login-card">
          <div className="login-tabs">
            <button
              className={`tab ${mode === 'login' ? 'active' : ''}`}
              onClick={() => setMode('login')}
            >
              Bejelentkezés
            </button>
            <button
              className={`tab ${mode === 'signup' ? 'active' : ''}`}
              onClick={() => setMode('signup')}
            >
              Regisztráció
            </button>
          </div>

          <form onSubmit={handleSubmit} className="login-form">
            {mode === 'signup' && (
              <div className="form-group">
                <label>Teljes név</label>
                <input
                  type="text"
                  value={displayName}
                  onChange={(e) => setDisplayName(e.target.value)}
                  placeholder="Kovács János"
                  required
                />
              </div>
            )}

            <div className="form-group">
              <label>E-mail cím</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="pelda@email.com"
                required
              />
            </div>

            <div className="form-group">
              <label>Jelszó</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
                minLength={6}
              />
            </div>

            <button 
              type="submit" 
              className="btn-login"
              disabled={loading}
            >
              {loading ? 'Folyamatban...' : (mode === 'login' ? 'Bejelentkezés' : 'Regisztráció')}
            </button>
          </form>
        </div>

        <div className="login-footer">
          <p>© 2024 Nagyvázsony - Túraútvonal Felfedező</p>
        </div>
      </div>

      {toast && (
        <Toast
          type={toast.type}
          message={toast.message}
          onClose={() => setToast(null)}
        />
      )}
    </div>
  );
}
