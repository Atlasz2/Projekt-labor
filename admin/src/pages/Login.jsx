import PropTypes from "prop-types";
import React, { useState } from "react";
import {
  browserLocalPersistence,
  sendPasswordResetEmail,
  setPersistence,
  signInWithEmailAndPassword,
  signOut,
} from "firebase/auth";
import { auth } from "../firebaseConfig";
import { resolveUserRole } from "../utils/resolveUserRole";
import "../styles/Login.css";

const AUTH_ERROR_MESSAGES = {
  "auth/invalid-email": "Érvénytelen email cím.",
  "auth/user-not-found": "Ez az email nincs regisztrálva.",
  "auth/wrong-password": "Hibás email vagy jelszó.",
  "auth/invalid-credential": "Hibás email vagy jelszó.",
  "auth/network-request-failed":
    "Nem sikerült elérni a bejelentkezési szervert. Ellenőrizd az internetkapcsolatot, és kapcsold ki a hirdetésblokkolót / VPN-t ezen az oldalon.",
  "auth/too-many-requests": "Túl sok sikertelen próbálkozás. Várj pár percet, és próbáld újra.",
};

function consumePersistedAccessError() {
  const persistedError = sessionStorage.getItem("admin_access_error");
  if (persistedError) {
    sessionStorage.removeItem("admin_access_error");
    return persistedError;
  }
  return "";
}

function EyeIcon({ visible }) {
  return visible ? (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94" />
      <path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19" />
      <line x1="1" y1="1" x2="23" y2="23" />
    </svg>
  ) : (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

EyeIcon.propTypes = {
  visible: PropTypes.bool.isRequired,
};

function CastleSvg() {
  return (
    <svg viewBox="0 0 400 200" xmlns="http://www.w3.org/2000/svg" className="castle-svg" aria-hidden="true">
      <rect width="400" height="200" fill="#b98c55" />
      <radialGradient id="sun" cx="20%" cy="20%" r="30%">
        <stop offset="0%" stopColor="rgba(255,233,180,0.7)" />
        <stop offset="100%" stopColor="transparent" />
      </radialGradient>
      <rect width="400" height="200" fill="url(#sun)" />
      <ellipse cx="200" cy="230" rx="260" ry="90" fill="#223128" />
      <rect x="120" y="130" width="160" height="50" fill="#181511" />
      <rect x="120" y="122" width="14" height="12" fill="#181511" />
      <rect x="144" y="122" width="14" height="12" fill="#181511" />
      <rect x="168" y="122" width="14" height="12" fill="#181511" />
      <rect x="192" y="122" width="14" height="12" fill="#181511" />
      <rect x="216" y="122" width="14" height="12" fill="#181511" />
      <rect x="240" y="122" width="14" height="12" fill="#181511" />
      <rect x="264" y="122" width="14" height="12" fill="#181511" />
      <rect x="256" y="100" width="36" height="82" fill="#1d1a15" />
      <rect x="252" y="92" width="10" height="12" fill="#1d1a15" />
      <rect x="268" y="92" width="10" height="12" fill="#1d1a15" />
      <rect x="284" y="92" width="12" height="12" fill="#1d1a15" />
      <path d="M272 180 L272 158 Q280 148 288 158 L288 180 Z" fill="#b98c55" />
      <rect x="60" y="70" width="60" height="110" fill="#201c17" />
      <path d="M60 70 Q90 44 120 70 Z" fill="#201c17" />
      <path d="M82 90 Q90 82 98 90 L98 106 L82 106 Z" fill="rgba(255,210,120,0.18)" />
      <rect x="56" y="62" width="10" height="12" fill="#201c17" />
      <rect x="72" y="62" width="10" height="12" fill="#201c17" />
      <rect x="88" y="62" width="10" height="12" fill="#201c17" />
      <rect x="104" y="62" width="10" height="12" fill="#201c17" />
      <rect x="120" y="62" width="10" height="12" fill="#201c17" />
      <path d="M80 180 L80 150 Q90 138 100 150 L100 180 Z" fill="#b98c55" />
    </svg>
  );
}

/** A visszajelzés szándékosan nem árulja el, létezik-e a fiók (különben az
 *  oldal alkalmas lenne admin e-mail-címek kipuhatolására). */
export const RESET_SENT_MESSAGE =
  "Ha ehhez a címhez tartozik admin fiók, elküldtük rá a jelszó-visszaállító levelet. Nézd meg a beérkező leveleidet (és a levélszemét mappát is).";

function Login() {
  const [email, setEmail] = useState(localStorage.getItem("last_admin_email") || "");
  const [password, setPassword] = useState("");
  const [error, setError] = useState(consumePersistedAccessError);
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  // Elfelejtett jelszó mód: ugyanazon a kártyán, külön űrlappal.
  const [resetMode, setResetMode] = useState(false);
  const [resetInfo, setResetInfo] = useState("");

  const handleReset = async (event) => {
    event.preventDefault();
    setError("");
    setResetInfo("");
    const normalizedEmail = email.trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalizedEmail)) {
      setError("Adj meg egy érvényes e-mail-címet.");
      return;
    }
    setLoading(true);
    auth.languageCode = "hu";
    // A levélben lévő link a jelszó beállítása után ide hoz vissza. Ha az
    // aktuális domain nincs engedélyezve a Firebase-ben, link nélkül küldjük.
    const continueSettings = { url: `${window.location.origin}/` };
    try {
      try {
        await sendPasswordResetEmail(auth, normalizedEmail, continueSettings);
      } catch (err) {
        if (err?.code !== "auth/unauthorized-continue-uri" && err?.code !== "auth/invalid-continue-uri") throw err;
        await sendPasswordResetEmail(auth, normalizedEmail);
      }
      setResetInfo(RESET_SENT_MESSAGE);
    } catch (err) {
      // A nem létező fiók is „sikeres” – ne derüljön ki, kinek van fiókja.
      if (err?.code === "auth/user-not-found") {
        setResetInfo(RESET_SENT_MESSAGE);
      } else {
        setError(AUTH_ERROR_MESSAGES[err.code] || "A levél küldése nem sikerült, próbáld újra.");
      }
    } finally {
      setLoading(false);
    }
  };

  const switchMode = (nextReset) => {
    setResetMode(nextReset);
    setError("");
    setResetInfo("");
  };

  const handleLogin = async (event) => {
    event.preventDefault();
    setError("");
    setLoading(true);

    try {
      const normalizedEmail = email.trim().toLowerCase();
      await setPersistence(auth, browserLocalPersistence);
      const credential = await signInWithEmailAndPassword(auth, normalizedEmail, password);

      const role = await resolveUserRole(credential.user);
      // A 'developer' az admin fölötti (platform-szintű) szerep – ő is beléphet.
      if (role !== "admin" && role !== "developer") {
        await signOut(auth);
        setError("Ehhez a fiókhoz nincs admin jogosultság.");
        setLoading(false);
        return;
      }

      localStorage.setItem("last_admin_email", normalizedEmail);
      // AdminAuthContext onAuthStateChanged picks up the new session automatically.
    } catch (err) {
      setError(AUTH_ERROR_MESSAGES[err.code] || `Bejelentkezési hiba: ${err.message}`);
      setLoading(false);
    }
  };

  return (
    <div className="login-shell">
      <div className="login-backdrop">
        <div className="login-orb orb-one" />
        <div className="login-orb orb-two" />
        <div className="login-grid-pattern" />
      </div>

      <div className="login-layout">
        <section className="login-story-panel">
          <h1>Nagyvázsony</h1>
          <div className="castle-frame">
            <CastleSvg />
          </div>
        </section>

        <section className="login-card-panel">
          <div className="login-card-surface">
            <div className="login-header">
              <h2>{resetMode ? "Elfelejtett jelszó" : "Admin belépés"}</h2>
              {resetMode && (
                <p className="panel-subtitle">
                  Add meg az admin fiókod e-mail-címét, és küldünk rá egy linket, amellyel új jelszót állíthatsz be.
                </p>
              )}
            </div>

            {error && (
              <div className="error-alert">
                <span className="error-icon">!</span>
                <p>{error}</p>
              </div>
            )}

            {resetInfo && (
              <div className="info-alert" role="status">
                <span className="info-icon">✓</span>
                <p>{resetInfo}</p>
              </div>
            )}

            {resetMode ? (
              <form onSubmit={handleReset} className="login-form">
                <div className="form-group">
                  <label htmlFor="reset-email">Email cím</label>
                  <input
                    type="email"
                    id="reset-email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="admin@nagyvazsony.hu"
                    required
                    disabled={loading}
                    autoFocus
                  />
                </div>
                <button type="submit" className="login-button" disabled={loading}>
                  {loading ? (
                    <span className="button-loading">
                      <span className="spinner" />
                      Küldés...
                    </span>
                  ) : (
                    "Visszaállító link küldése"
                  )}
                </button>
                <button type="button" className="link-button" onClick={() => switchMode(false)} disabled={loading}>
                  ← Vissza a belépéshez
                </button>
              </form>
            ) : (
            <form onSubmit={handleLogin} className="login-form">
              <div className="form-group">
                <label htmlFor="email">Email cím</label>
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
                <label htmlFor="password">Jelszó</label>
                <div className="password-wrap">
                  <input
                    type={showPassword ? "text" : "password"}
                    id="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;"
                    required
                    disabled={loading}
                  />
                  <button
                    type="button"
                    className="password-toggle"
                    onClick={() => setShowPassword((visible) => !visible)}
                    tabIndex={-1}
                    aria-label={showPassword ? "Jelszó elrejtése" : "Jelszó megjelenítése"}
                  >
                    <EyeIcon visible={showPassword} />
                  </button>
                </div>
              </div>

              <button type="submit" className="login-button" disabled={loading}>
                {loading ? (
                  <span className="button-loading">
                    <span className="spinner" />
                    Belépés folyamatban...
                  </span>
                ) : (
                  "Belépés a vezérlőközpontba"
                )}
              </button>
              <button type="button" className="link-button" onClick={() => switchMode(true)} disabled={loading}>
                Elfelejtettem a jelszavam
              </button>
            </form>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}

export default Login;
