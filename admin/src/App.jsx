import React, { Suspense, lazy, useState, useEffect } from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { auth } from "./firebaseConfig";
import { onAuthStateChanged, signOut } from "firebase/auth";

const Layout = lazy(() => import("./components/Layout"));
const Login = lazy(() => import("./pages/Login"));
const Dashboard = lazy(() => import("./pages/Dashboard"));
const Trips = lazy(() => import("./pages/Trips"));
const Stations = lazy(() => import("./pages/Stations"));
const Map = lazy(() => import("./pages/Map"));
const Users = lazy(() => import("./pages/Users"));
const About = lazy(() => import("./pages/About"));
const Events = lazy(() => import("./pages/Events"));
const Accommodations = lazy(() => import("./pages/Accommodations"));
const Restaurants = lazy(() => import("./pages/Restaurants"));
const Contact = lazy(() => import("./pages/Contact"));
const SeedDatabase = lazy(() => import("./pages/SeedDatabase"));

function FullPageLoader() {
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

function App() {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [userRole, setUserRole] = useState(localStorage.getItem("admin_role") || "user");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    try {
      const unsubscribe = onAuthStateChanged(auth, (user) => {
        setIsLoggedIn(!!user);
        setLoading(false);

        if (user) {
          localStorage.setItem("demo_logged_in", "true");
          localStorage.setItem("admin_email", user.email || "");
          localStorage.setItem("admin_uid", user.uid || "");
          const role = (localStorage.getItem("admin_role") || "user").toLowerCase();
          setUserRole(role);
        } else {
          localStorage.removeItem("demo_logged_in");
          localStorage.removeItem("admin_email");
          localStorage.removeItem("admin_role");
          localStorage.removeItem("admin_uid");
          setUserRole("user");
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
      localStorage.removeItem("admin_email");
      localStorage.removeItem("admin_role");
      localStorage.removeItem("admin_uid");
      window.location.href = "/";
    } catch (err) {
      console.error("Logout hiba:", err);
    }
  };

  if (loading) {
    return <FullPageLoader />;
  }

  const adminOnly = (element) =>
    userRole === "admin" ? element : <Navigate to="/dashboard" replace />;

  return (
    <BrowserRouter>
      <Suspense fallback={<FullPageLoader />}>
        <Routes>
          <Route
            path="/"
            element={isLoggedIn ? <Navigate to="/dashboard" /> : <Login />}
          />

          {isLoggedIn ? (
            <Route path="/" element={<Layout />}>
              <Route path="dashboard" element={<Dashboard />} />
              <Route path="map" element={<Map />} />
              <Route path="users" element={<Users />} />

              <Route path="trips" element={adminOnly(<Trips />)} />
              <Route path="stations" element={adminOnly(<Stations />)} />
              <Route path="about" element={adminOnly(<About />)} />
              <Route path="events" element={adminOnly(<Events />)} />
              <Route path="accommodations" element={adminOnly(<Accommodations />)} />
              <Route path="restaurants" element={adminOnly(<Restaurants />)} />
              <Route path="contact" element={adminOnly(<Contact />)} />
              <Route path="seed-database" element={adminOnly(<SeedDatabase />)} />
            </Route>
          ) : (
            <Route path="*" element={<Navigate to="/" />} />
          )}
        </Routes>
      </Suspense>
    </BrowserRouter>
  );
}

export default App;
