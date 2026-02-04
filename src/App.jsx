import React, { useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { useAppStore } from './store/appStore';
import { AuthService } from './services/authService';
import { Header } from './components/Header';
import './App.css';
import 'leaflet/dist/leaflet.css';

// Pages
import LoginPage from './pages/LoginPage';
import HomePage from './pages/HomePage';
import TrailDetailsPage from './pages/TrailDetailsPage';
import AdminPanel from './pages/AdminPanel';

// Protected Route Component
function ProtectedRoute({ children }) {
  const { user } = useAppStore();
  
  if (!user) {
    return <Navigate to="/" replace />;
  }
  
  return children;
}

function App() {
  const { user, setUser } = useAppStore();

  useEffect(() => {
    // Auth state listener
    const unsubscribe = AuthService.getCurrentUser((currentUser) => {
      console.log('App.jsx - User state changed:', currentUser);
      setUser(currentUser);
    });

    return unsubscribe;
  }, [setUser]);

  useEffect(() => {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/service-worker.js')
        .then(reg => console.log('Service Worker regisztrálva'))
        .catch(err => console.error('SW error:', err));
    }
  }, []);

  console.log('App.jsx render - Current user:', user);

  return (
    <Router>
      <Routes>
        {/* Login - Főképernyő - Ha be van jelentkezve, átirányít */}
        <Route path="/" element={
          user ? <Navigate to="/admin" replace /> : <LoginPage />
        } />
        
        {/* Nyilvános oldalak */}
        <Route path="/home" element={
          <>
            <Header />
            <HomePage />
          </>
        } />
        <Route path="/trail/:id" element={
          <>
            <Header />
            <TrailDetailsPage />
          </>
        } />
        
        {/* Admin Panel - Védett */}
        <Route path="/admin" element={
          <ProtectedRoute>
            <Header />
            <AdminPanel />
          </ProtectedRoute>
        } />
      </Routes>
    </Router>
  );
}

export default App;
