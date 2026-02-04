import React, { useState } from 'react';
import { auth } from '../firebaseConfig';
import { signInWithEmailAndPassword } from 'firebase/auth';
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
      await signInWithEmailAndPassword(auth, email, password);
      localStorage.setItem('demo_logged_in', 'true');
      window.location.href = '/admin/dashboard';
    } catch (err) {
      console.error('Bejelentkezési hiba:', err);
      
      // Friendly error messages
      if (err.code === 'auth/invalid-email') {
        setError('Érvénytelen email cím');
      } else if (err.code === 'auth/user-not-found' || err.code === 'auth/wrong-password') {
        setError('Hibás email vagy jelszó');
      } else if (err.code === 'auth/invalid-credential') {
        setError('Hibás bejelentkezési adatok');
      } else {
        setError('Bejelentkezési hiba történt');
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-container">
      <div className="login-box">
        <h1>Nagyvázsony Admin</h1>
        <p className="login-subtitle">Túraútvonal Kezelő</p>

        {error && <div className="error-message">{error}</div>}

        <form onSubmit={handleLogin}>
          <div className="form-group">
            <label htmlFor="email">Email</label>
            <input
              type="email"
              id="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="pelda@email.com"
              required
              disabled={loading}
            />
          </div>

          <div className="form-group">
            <label htmlFor="password">Jelszó</label>
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
            {loading ? 'Bejelentkezés...' : 'Bejelentkezés'}
          </button>
        </form>

        <p className="login-info">
          ℹ️ Firebase Authentication-nel működik
        </p>
      </div>
    </div>
  );
}

export default Login;
