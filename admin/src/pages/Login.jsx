import React, { useEffect, useState } from 'react';
import { auth, db } from '../firebaseConfig';
import { browserLocalPersistence, setPersistence, signInWithEmailAndPassword } from 'firebase/auth';
import { collection, doc, getDoc, getDocs, limit, query, where } from 'firebase/firestore';
import '../styles/Login.css';

function Login() {
  const [email, setEmail] = useState(localStorage.getItem('last_admin_email') || '');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [adminAccounts, setAdminAccounts] = useState([]);
  const [accountsLoading, setAccountsLoading] = useState(true);

  useEffect(() => {
    fetchAdminAccounts();
  }, []);

  const fetchAdminAccounts = async () => {
    setAccountsLoading(true);
    try {
      const adminsQuery = query(collection(db, 'users'), where('role', '==', 'admin'));
      const snapshot = await getDocs(adminsQuery);

      const accounts = snapshot.docs
        .map((item) => {
          const data = item.data();
          const fallbackEmail = item.id.includes('@') ? item.id : '';
          const userEmail = (data.email || fallbackEmail || '').trim();
          if (!userEmail) return null;

          return {
            id: item.id,
            email: userEmail,
            name: data.name || data.userName || 'Admin',
          };
        })
        .filter(Boolean)
        .sort((a, b) => a.email.localeCompare(b.email, 'hu'));

      setAdminAccounts(accounts);
    } catch (err) {
      console.error('Admin account lista hiba:', err);
      setAdminAccounts([]);
    } finally {
      setAccountsLoading(false);
    }
  };

  const getUserDocByEmail = async (userEmail) => {
    const directDoc = await getDoc(doc(db, 'users', userEmail));
    if (directDoc.exists()) {
      return directDoc;
    }

    const byEmailQuery = query(collection(db, 'users'), where('email', '==', userEmail), limit(1));
    const byEmailSnapshot = await getDocs(byEmailQuery);
    if (!byEmailSnapshot.empty) {
      return byEmailSnapshot.docs[0];
    }

    return null;
  };

  const handleLogin = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const normalizedEmail = email.trim().toLowerCase();
      await setPersistence(auth, browserLocalPersistence);
      const userCredential = await signInWithEmailAndPassword(auth, normalizedEmail, password);
      console.log('✅ Firebase Auth sikeres', userCredential.user.uid);

      const userDoc = await getUserDocByEmail(normalizedEmail);
      const userData = userDoc?.data?.() || {};
      const role = (userData.role || 'user').toLowerCase();

      localStorage.setItem('demo_logged_in', 'true');
      localStorage.setItem('admin_email', normalizedEmail);
      localStorage.setItem('admin_role', role);
      localStorage.setItem('last_admin_email', normalizedEmail);

      if (!userDoc) {
        console.warn('⚠️ Nincs users doc ehhez az emailhez, default szerepkör: user');
      }

      window.location.href = '/';
    } catch (err) {
      console.error('Bejelentkezési hiba:', err.code, err.message);

      if (err.code === 'auth/invalid-email') {
        setError('⚠️ Érvénytelen email cím');
      } else if (err.code === 'auth/user-not-found') {
        setError('⚠️ Ez az email nincs regisztrálva');
      } else if (err.code === 'auth/wrong-password' || err.code === 'auth/invalid-credential') {
        setError('⚠️ Hibás email vagy jelszó');
      } else {
        setError('❌ Bejelentkezési hiba: ' + err.message);
      }
      setLoading(false);
    }
  };

  const handleAccountPick = (userEmail) => {
    setEmail(userEmail);
    setError('');
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
            {accountsLoading ? (
              <div className="account-picker-box">Admin fiókok betöltése...</div>
            ) : adminAccounts.length > 0 ? (
              <div className="account-picker-box">
                <div className="account-picker-title">Gyors fiókválasztás</div>
                <div className="account-list">
                  {adminAccounts.map((account) => (
                    <button
                      key={account.id}
                      type="button"
                      className={`account-chip ${email === account.email ? 'active' : ''}`}
                      onClick={() => handleAccountPick(account.email)}
                      disabled={loading}
                    >
                      {account.email}
                    </button>
                  ))}
                </div>
              </div>
            ) : null}

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
              Több felhasználós belépés támogatott (kijelentkezés után új belépés)
            </p>
            <div className="credentials">
              {adminAccounts.slice(0, 3).map((account) => (
                <code key={account.id}>{account.email}</code>
              ))}
            </div>
          </div>
        </div>

        <div className="login-info-box">
          <p><span>✅</span> Firebase Authentication</p>
          <p><span>👥</span> Több felhasználós login</p>
          <p><span>🧾</span> Szerepkör mentés (admin/user)</p>
        </div>
      </div>
    </div>
  );
}

export default Login;

