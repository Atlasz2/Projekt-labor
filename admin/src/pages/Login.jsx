import React, { useState } from 'react';
import { auth, db } from '../firebaseConfig';
import { signInWithEmailAndPassword, signOut } from 'firebase/auth';
import { getDoc, doc } from 'firebase/firestore';
import '../styles/Login.css';

function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleLogin = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      // 1. Firebase Auth bejelentkezés
      const userCredential = await signInWithEmailAndPassword(auth, email, password);
      console.log('✅ Firebase Auth sikeres');

      // 2. Firestore-ban ellenőrizni: van-e admin jogosultság
      const userDoc = await getDoc(doc(db, 'users', email));
      
      if (!userDoc.exists()) {
        console.error('❌ Nincs felhasználó a Firestore-ban');
        await signOut(auth); // Kijelentkeztet
        setError('❌ Nincs admin jogosultság!');
        setLoading(false);
        return;
      }

      const userData = userDoc.data();
      
      if (userData.role !== 'admin') {
        console.error('❌ A felhasználó nem admin:', userData.role);
        await signOut(auth); // Kijelentkeztet
        setError('❌ Nincs admin jogosultság! (Szerepkör: ' + userData.role + ')');
        setLoading(false);
        return;
      }

      console.log('✅ Admin jogosultság ellenőrizve');
      localStorage.setItem('demo_logged_in', 'true');
      localStorage.setItem('admin_email', email);
      window.location.href = '/';

    } catch (err) {
      console.error('Bejelentkezési hiba:', err.code, err.message);
      
      if (err.code === 'auth/invalid-email') {
        setError('⚠️ Érvénytelen email cím');
      } else if (err.code === 'auth/user-not-found') {
        setError('⚠️ Ez az email nincs regisztrálva');
      } else if (err.code === 'auth/wrong-password' || err.code === 'auth/invalid-credential') {
        setError('⚠️ Hibás email vagy jelszó');
      } else if (err.message.includes('admin')) {
        setError(err.message);
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

            <button 
              type="submit" 
              className="login-button" 
              disabled={loading}
            >
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
              Firebase Admin Auth
            </p>
            <div className="credentials">
              <code>admin@nagyvazsony.hu</code>
            </div>
          </div>
        </div>

        <div className="login-info-box">
          <p><span>✅</span> Firebase Authentication</p>
          <p><span>🔐</span> Admin Role Ellenőrzés</p>
          <p><span>🗺️</span> Túraútvonal szerkesztés</p>
        </div>
      </div>
    </div>
  );
}

export default Login;

