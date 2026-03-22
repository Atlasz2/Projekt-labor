import React, { useEffect, useState } from 'react';
import { auth } from '../firebaseConfig';
import {
  browserLocalPersistence,
  setPersistence,
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';
import '../styles/Login.css';
import { resolveUserRole } from '../utils/resolveUserRole';

function Login() {
  const [email, setEmail] = useState(localStorage.getItem('last_admin_email') || '');
  const [password, setPassword] = useState('');
  const [error, setError] = useState(sessionStorage.getItem('admin_access_error') || '');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const persistedError = sessionStorage.getItem('admin_access_error');
    if (persistedError) {
      setError(persistedError);
      sessionStorage.removeItem('admin_access_error');
    }
  }, []);

  const handleLogin = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const normalizedEmail = email.trim().toLowerCase();
      await setPersistence(auth, browserLocalPersistence);
      const userCredential = await signInWithEmailAndPassword(
        auth,
        normalizedEmail,
        password,
      );

      const resolvedRole = await resolveUserRole(userCredential.user);

      if (resolvedRole !== 'admin') {
        await signOut(auth);
        localStorage.removeItem('demo_logged_in');
        localStorage.removeItem('admin_email');
        localStorage.removeItem('admin_role');
        localStorage.removeItem('admin_uid');
        setError('⚠️ Ehhez a fiókhoz nincs admin jogosultság');
        setLoading(false);
        return;
      }

      localStorage.setItem('demo_logged_in', 'true');
      localStorage.setItem('admin_email', normalizedEmail);
      localStorage.setItem('admin_role', resolvedRole);
      localStorage.setItem('admin_uid', userCredential.user.uid);
      localStorage.setItem('last_admin_email', normalizedEmail);

      window.location.href = '/';
    } catch (err) {
      if (err.code === 'auth/invalid-email') {
        setError('⚠️ Érvénytelen email cím');
      } else if (err.code === 'auth/user-not-found') {
        setError('⚠️ Ez az email nincs regisztrálva');
      } else if (
        err.code === 'auth/wrong-password' ||
        err.code === 'auth/invalid-credential'
      ) {
        setError('⚠️ Hibás email vagy jelszó');
      } else {
        setError('❌ Bejelentkezési hiba: ' + err.message);
      }
      setLoading(false);
    }
  };

  return (
    <div className="login-container">
      <div className="login-background">
        <div className="shape shape-1"></div>
        <div className="shape shape-2"></div>
        <div className="shape shape-3"></div>
      </div>

      <div className="login-content">
        <div className="login-card">
          <div className="login-header">
            <div className="logo">🏔️</div>
            <h1>Nagyvázsony</h1>
            <p className="subtitle">Túraútvonal Kezelő</p>
            <p className="tagline">Admin Felület</p>
          </div>

          {error && (
            <div className="error-alert">
              <span className="error-icon">⚠️</span>
              <p>{error}</p>
            </div>
          )}

          <form onSubmit={handleLogin} className="login-form">
            <div className="form-group">
              <label htmlFor="email">
                <span className="label-icon">✉️</span>
                Email Cím
              </label>
              <input
                type="email"
                id="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="admin@nagyvazsony.hu"
                required
                disabled={loading}
                autoFocus
              />
            </div>

            <div className="form-group">
              <label htmlFor="password">
                <span className="label-icon">🔐</span>
                Jelszó
              </label>
              <input
                type="password"
                id="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
                disabled={loading}
              />
            </div>

            <button type="submit" className="login-button" disabled={loading}>
              {loading ? (
                <span className="button-loading">
                  <span className="spinner"></span>
                  Bejelentkezés...
                </span>
              ) : (
                <span>🔓 Bejelentkezés</span>
              )}
            </button>
          </form>

          <div className="login-footer">
            <p className="test-info">
              <span className="info-icon">🔒</span>
              Az admin felület csak admin jogosultságú felhasználóknak érhető el.
            </p>
          </div>
        </div>

        <div className="login-info-box">
          <p><span>✅</span> Firebase Authentication</p>
          <p><span>🛡️</span> Admin szerepkör ellenőrzés</p>
          <p><span>🚫</span> Jogosulatlan hozzáférés tiltása</p>
        </div>
      </div>
    </div>
  );
}

export default Login;
