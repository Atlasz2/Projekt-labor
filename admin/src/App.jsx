import React, { useState, useEffect } from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { auth } from "./firebaseConfig";
import { onAuthStateChanged, signOut } from "firebase/auth";
import Layout from "./components/Layout";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import Trips from "./pages/Trips";
import Stations from "./pages/Stations";
import Map from "./pages/Map";
import Users from "./pages/Users";
import About from "./pages/About";
import Events from "./pages/Events";
import Accommodations from "./pages/Accommodations";
import Restaurants from "./pages/Restaurants";
import Contact from "./pages/Contact";
import SeedDatabase from "./pages/SeedDatabase";

function App() {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    try {
      const unsubscribe = onAuthStateChanged(auth, (user) => {
        setIsLoggedIn(!!user);
        setLoading(false);

        if (user) {
          localStorage.setItem("demo_logged_in", "true");
        } else {
          localStorage.removeItem("demo_logged_in");
        }
      });

      return () => unsubscribe();
    } catch (err) {
      console.error("Auth init hiba:", err);
      setLoading(false);
    }
  }, []);

  window.handleDemoLogout = async () => {
    try {
      await signOut(auth);
      localStorage.removeItem("demo_logged_in");
      window.location.href = "/";
    } catch (err) {
      console.error("Logout hiba:", err);
    }
  };

  if (loading) {
    return (
      <div
        style={{
          display: "flex",
          justifyContent: "center",
          alignItems: "center",
          height: "100vh",
          fontSize: "16px",
        }}
      >
        <p>Betöltés...</p>
      </div>
    );
  }

  return (
    <BrowserRouter>
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
            <Route path="about" element={<About />} />
            <Route path="events" element={<Events />} />
            <Route path="accommodations" element={<Accommodations />} />
            <Route path="restaurants" element={<Restaurants />} />
            <Route path="contact" element={<Contact />} />
            <Route path="seed-database" element={<SeedDatabase />} />
          </Route>
        ) : (
          <Route path="*" element={<Navigate to="/" />} />
        )}
      </Routes>
    </BrowserRouter>
  );
}

export default App;
