import React, { useState } from 'react';
import { AuthService } from '../services/authService';
import '../styles/AuthModal.css';

export const AuthModal = ({ onClose, onSuccess }) => {
  const [mode, setMode] = useState('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      if (mode === 'signup') {
        await AuthService.signup(email, password, displayName);
      } else {
        await AuthService.login(email, password);
      }
      onSuccess();
      onClose();
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-overlay">
      <div className="auth-card">
        <div className="auth-header">
          <h2>{mode === 'login' ? 'Bejelentkezés' : 'Regisztráció'}</h2>
          <p>{mode === 'login' ? 'Lépj be a kezelőfelülethez' : 'Hozz létre új fiókot'}</p>
        </div>

        {error && <div className="auth-error">{error}</div>}

        <form onSubmit={handleSubmit} className="auth-form">
          {mode === 'signup' && (
            <input
              type="text"
              placeholder="Teljes név"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              required
            />
          )}

          <input
            type="email"
            placeholder="E-mail"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />

          <input
            type="password"
            placeholder="Jelszó"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />

          <button type="submit" disabled={loading}>
            {loading ? 'Folyamatban...' : (mode === 'login' ? 'Bejelentkezés' : 'Regisztráció')}
          </button>
        </form>

        <div className="auth-footer">
          <span>{mode === 'login' ? 'Nincs fiókod?' : 'Van már fiókod?'}</span>
          <button
            type="button"
            onClick={() => {
              setMode(mode === 'login' ? 'signup' : 'login');
              setError('');
            }}
          >
            {mode === 'login' ? 'Regisztráció' : 'Bejelentkezés'}
          </button>
        </div>

        <button className="auth-close" onClick={onClose}>✕</button>
      </div>
    </div>
  );
};
