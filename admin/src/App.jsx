import React, { Suspense, lazy, useEffect, useState, useMemo } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AdminAuthProvider, useAdminAuth } from './context/AdminAuthContext';
import { createTheme, ThemeProvider } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';

const buildMuiTheme = (isDark) => createTheme({
  palette: {
    mode: isDark ? 'dark' : 'light',
    primary:    { main: '#2563eb', dark: '#1d4ed8', light: '#60a5fa' },
    secondary:  { main: '#0ea5e9' },
    error:      { main: '#dc2626' },
    warning:    { main: '#d97706' },
    success:    { main: '#059669' },
    background: isDark
      ? { default: '#0c1526', paper: '#182234' }
      : { default: '#f1f5f9', paper: '#ffffff' },
    text: isDark
      ? { primary: '#e2e8f0', secondary: '#94a3b8' }
      : { primary: '#0f172a', secondary: '#64748b' },
    divider: isDark ? '#2d3f55' : 'rgba(15,23,42,0.12)',
  },
  typography: {
    fontFamily: "'Inter', system-ui, -apple-system, sans-serif",
    button: { textTransform: 'none', fontWeight: 600 },
  },
  shape: { borderRadius: 10 },
  components: {
    MuiButton: {
      styleOverrides: {
        root: { boxShadow: 'none', '&:hover': { boxShadow: '0 4px 12px rgba(37,99,235,0.2)' } },
      },
    },
    MuiPaper: {
      styleOverrides: {
        root: {
          boxShadow: isDark
            ? '0 1px 4px rgba(0,0,0,0.4)'
            : '0 1px 4px rgba(15,23,42,0.08), 0 4px 16px rgba(15,23,42,0.05)',
        },
      },
    },
    MuiTableHead: {
      styleOverrides: {
        root: { '& .MuiTableCell-head': { background: '#0f172a', color: '#e2e8f0', fontWeight: 700 } },
      },
    },
  },
});

const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 60_000, retry: 1 } },
});

const Layout         = lazy(() => import('./components/Layout'));
const Login          = lazy(() => import('./pages/Login'));
const Dashboard      = lazy(() => import('./pages/Dashboard'));
const Trips          = lazy(() => import('./pages/Trips'));
const Stations       = lazy(() => import('./pages/Stations'));
const Map            = lazy(() => import('./pages/Map'));
const Users          = lazy(() => import('./pages/Users'));
const About          = lazy(() => import('./pages/About'));
const Events         = lazy(() => import('./pages/Events'));
const Accommodations = lazy(() => import('./pages/Accommodations'));
const Restaurants    = lazy(() => import('./pages/Restaurants'));
const Contact        = lazy(() => import('./pages/Contact'));
const SeedDatabase   = lazy(() => import('./pages/SeedDatabase'));
const Achievements   = lazy(() => import('./pages/Achievements'));
const BugReports     = lazy(() => import('./pages/BugReports'));

function FullPageLoader() {
  return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100vh', fontSize: '16px', color: '#64748b' }}>
      <p>Betöltés...</p>
    </div>
  );
}

function AppRoutes() {
  const { isLoggedIn, userRole, loading } = useAdminAuth();

  if (loading) return <FullPageLoader />;

  const adminOnly = (element) =>
    userRole === 'admin' ? element : <Navigate to="/" replace />;

  return (
    <BrowserRouter>
      <Suspense fallback={<FullPageLoader />}>
        <Routes>
          <Route path="/" element={isLoggedIn ? <Navigate to="/dashboard" /> : <Login />} />

          {isLoggedIn ? (
            <Route path="/" element={<Layout />}>
              <Route path="dashboard"      element={adminOnly(<Dashboard />)} />
              <Route path="map"            element={adminOnly(<Map />)} />
              <Route path="users"          element={adminOnly(<Users />)} />
              <Route path="trips"          element={adminOnly(<Trips />)} />
              <Route path="stations"       element={adminOnly(<Stations />)} />
              <Route path="about"          element={adminOnly(<About />)} />
              <Route path="events"         element={adminOnly(<Events />)} />
              <Route path="accommodations" element={adminOnly(<Accommodations />)} />
              <Route path="restaurants"    element={adminOnly(<Restaurants />)} />
              <Route path="contact"        element={adminOnly(<Contact />)} />
              <Route path="achievements"   element={adminOnly(<Achievements />)} />
              <Route path="bug-reports"    element={adminOnly(<BugReports />)} />
              <Route path="seed-database"  element={adminOnly(<SeedDatabase />)} />
              <Route path="*"              element={<Navigate to="/dashboard" replace />} />
            </Route>
          ) : (
            <Route path="*" element={<Navigate to="/" />} />
          )}
        </Routes>
      </Suspense>
    </BrowserRouter>
  );
}

function App() {
  const [isDark, setIsDark] = useState(
    () => document.documentElement.classList.contains('dark')
      || localStorage.getItem('adminDarkMode') === 'true'
  );

  useEffect(() => {
    if (localStorage.getItem('adminDarkMode') === 'true') {
      document.documentElement.classList.add('dark');
    }
    // Keep the MUI theme in sync with the html.dark class toggled from the sidebar
    const observer = new MutationObserver(() => {
      setIsDark(document.documentElement.classList.contains('dark'));
    });
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['class'],
    });
    return () => observer.disconnect();
  }, []);

  const muiTheme = useMemo(() => buildMuiTheme(isDark), [isDark]);

  return (
    <ThemeProvider theme={muiTheme}>
      <CssBaseline />
      <QueryClientProvider client={queryClient}>
        <AdminAuthProvider>
          <AppRoutes />
        </AdminAuthProvider>
      </QueryClientProvider>
    </ThemeProvider>
  );
}

export default App;