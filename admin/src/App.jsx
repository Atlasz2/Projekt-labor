import React, { useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { auth } from './firebaseConfig';
import { onAuthStateChanged, signOut } from 'firebase/auth';
import Layout from './components/Layout';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Trips from './pages/Trips';
import Stations from './pages/Stations';
import Map from './pages/Map';
import Users from './pages/Users';

function App() {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Firebase auth state listener
    const unsubscribe = onAuthStateChanged(auth, (user) => {
      setIsLoggedIn(!!user);
      setLoading(false);
      
      if (user) {
        localStorage.setItem('demo_logged_in', 'true');
      } else {
        localStorage.removeItem('demo_logged_in');
      }
    });

    return () => unsubscribe();
  }, []);

  // Logout handler for Layout component
  window.handleDemoLogout = async () => {
    try {
      await signOut(auth);
      localStorage.removeItem('demo_logged_in');
      window.location.href = '/admin/';
    } catch (err) {
      console.error('Kijelentkezési hiba:', err);
    }
  };

  if (loading) {
    return (
      <div style={{ 
        display: 'flex', 
        justifyContent: 'center', 
        alignItems: 'center', 
        height: '100vh' 
      }}>
        <p>Betöltés...</p>
      </div>
    );
  }

  return (
    <BrowserRouter basename="/admin">
      <Routes>
        <Route 
          path="/" 
          element={isLoggedIn ? <Navigate to="/dashboard" /> : <Login />} 
        />
        
        {isLoggedIn ? (
          <Route path="/" element={<Layout />}>
            <Route path="dashboard" element={<Dashboard />} />
            <Route path="trips" element={<Trips />} />
            <Route path="stations" element={<Stations />} />
            <Route path="map" element={<Map />} />
            <Route path="users" element={<Users />} />
          </Route>
        ) : (
          <Route path="*" element={<Navigate to="/" />} />
        )}
      </Routes>
    </BrowserRouter>
  );
}

export default App;
