import React, { useState, useEffect } from 'react';
import { collection, addDoc, getDocs, deleteDoc, doc, updateDoc, serverTimestamp, GeoPoint } from 'firebase/firestore';
import { db, auth } from '../firebase';
import { useAuthState } from 'react-firebase-hooks/auth';
import L from 'leaflet';
import 'leaflet-routing-machine/dist/leaflet-routing-machine.css';
import 'leaflet-routing-machine';
import { Toast } from '../components/Toast';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { StationModal } from '../components/admin/StationModal';
import { ProgramModal } from '../components/admin/ProgramModal';
import { TripModal } from '../components/admin/TripModal';
import { TripMap } from '../components/admin/TripMap';
import '../styles/AdminPanel.css';

export default function AdminPanel() {
  const [user] = useAuthState(auth);
  const [activeTab, setActiveTab] = useState('stations');
  const [stations, setStations] = useState([]);
  const [programs, setPrograms] = useState([]);
  const [trips, setTrips] = useState([]);
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState(null);
  const [showStationModal, setShowStationModal] = useState(false);
  const [showProgramModal, setShowProgramModal] = useState(false);
  const [showTripModal, setShowTripModal] = useState(false);
  const [editingStation, setEditingStation] = useState(null);
  const [editingProgram, setEditingProgram] = useState(null);
  const [editingTrip, setEditingTrip] = useState(null);
  const [confirmDialog, setConfirmDialog] = useState(null);

  // Fetch data on mount and tab change
  useEffect(() => {
    if (user) {
      fetchData();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user, activeTab]);

  const fetchData = async () => {
    setLoading(true);
    try {
      if (activeTab === 'stations') {
        await fetchStations();
      } else if (activeTab === 'programs') {
        await fetchPrograms();
      } else if (activeTab === 'trips') {
        await fetchTrips();
      } else if (activeTab === 'users') {
        await fetchUsers();
      }
    } catch (error) {
      console.error('Hiba az adatok betöltésekor:', error);
      setToast({ type: 'error', message: 'Hiba az adatok betöltésekor' });
    } finally {
      setLoading(false);
    }
  };

  const fetchStations = async () => {
    try {
      console.log('🔍 Állomások betöltése...');
      
      // Túrák betöltése
      const tripsSnapshot = await getDocs(collection(db, 'trips'));
      const tripsData = tripsSnapshot.docs.map(doc => ({ 
        id: doc.id, 
        ...doc.data() 
      }));
      console.log('✅ Túrák betöltve:', tripsData.length);
      setTrips(tripsData);

      // Állomások betöltése - EGYSZERŰ getDocs, nincs where/orderBy
      const stationsSnapshot = await getDocs(collection(db, 'stations'));
      console.log('📊 Firestore stations snapshot:', stationsSnapshot.size, 'dokumentum');
      
      // Manuális feldolgozás, szűrés és rendezés
      const stationsData = stationsSnapshot.docs
        .map(doc => {
          const data = doc.data();
          console.log('📍 Állomás raw adat:', doc.id, data);
          
          return {
            id: doc.id,
            name: data.name || 'Névtelen állomás',
            description: data.description || '',
            location: data.location || null,
            orderIndex: data.orderIndex || 0,
            qrCode: data.qrCode || '',
            points: data.points ?? 10,
            isActive: data.isActive === true,
            tripId: data.tripId || '',
            tripName: tripsData.find(t => t.id === data.tripId)?.name || 'Nincs hozzárendelve'
          };
        })
        .sort((a, b) => a.orderIndex - b.orderIndex); // Manuális rendezés

      console.log('✅ Állomások feldolgozva és rendezve:', stationsData.length);
      
      setStations(stationsData);
      
      if (stationsData.length === 0) {
        console.warn('⚠️ Nincs állomás az adatbázisban!');
        setToast({ 
          type: 'info', 
          message: 'Még nincsenek állomások az adatbázisban. Hozz létre egyet!' 
        });
      }
    } catch (error) {
      console.error('❌ Hiba az állomások betöltésekor:', error);
      setToast({ type: 'error', message: `Hiba az állomások betöltésekor: ${error.message}` });
    }
  };

  const fetchPrograms = async () => {
    try {
      console.log('🔍 Programok betöltése...');
      const snapshot = await getDocs(collection(db, 'programs'));
      console.log('📊 Firestore programs snapshot:', snapshot.size, 'dokumentum');
      
      const programsData = snapshot.docs.map(doc => ({ 
        id: doc.id, 
        ...doc.data() 
      }));
      
      console.log('✅ Programok betöltve:', programsData);
      
      const sortedPrograms = programsData.sort((a, b) => {
        if (!a.date || !b.date) return 0;
        return b.date.seconds - a.date.seconds;
      });
      
      setPrograms(sortedPrograms);
      
      if (programsData.length === 0) {
        console.warn('⚠️ Nincs program az adatbázisban!');
      }
    } catch (error) {
      console.error('❌ Hiba a programok betöltésekor:', error);
      setToast({ type: 'error', message: `Hiba a programok betöltésekor: ${error.message}` });
    }
  };

  const fetchTrips = async () => {
    const snapshot = await getDocs(collection(db, 'trips'));
    setTrips(snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
  };

  const fetchUsers = async () => {
    const snapshot = await getDocs(collection(db, 'users'));
    setUsers(snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
  };

  // STATION ACTIONS
  const handleCreateStation = () => {
    setEditingStation(null);
    setShowStationModal(true);
  };

  const handleEditStation = (station) => {
    setEditingStation(station);
    setShowStationModal(true);
  };

  const handleDeleteStation = (station) => {
    setConfirmDialog({
      title: 'Állomás törlése',
      message: `Biztosan törölni szeretnéd a(z) "${station.name}" állomást?`,
      onConfirm: async () => {
        try {
          await deleteDoc(doc(db, 'stations', station.id));
          setToast({ type: 'success', message: 'Állomás törölve!' });
          fetchStations();
        } catch (error) {
          setToast({ type: 'error', message: 'Hiba a törlés során' });
        }
      }
    });
  };
  const generateQrCode = (name) => {
    if (!name) return '';
    return name
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/(^-|-$)/g, '');
  };
  const handleSaveStation = async (stationData) => {
    try {
      console.log('💾 Állomás mentése:', stationData);

      const qrCodeValue = (stationData.qrCode || generateQrCode(stationData.name)).trim();
      const pointsValue = parseInt(stationData.points, 10);
      
      const dataToSave = {
        name: stationData.name,
        description: stationData.description,
        location: new GeoPoint(
          parseFloat(stationData.latitude),
          parseFloat(stationData.longitude)
        ),
        orderIndex: parseInt(stationData.orderIndex) || 0,
        qrCode: qrCodeValue,
        points: Number.isFinite(pointsValue) ? pointsValue : 10,
        tripId: stationData.tripId
      };

      console.log('💾 Firestore-ba mentendő adat:', dataToSave);

      if (editingStation) {
        await updateDoc(doc(db, 'stations', editingStation.id), dataToSave);
        console.log('✅ Állomás frissítve:', editingStation.id);
        setToast({ type: 'success', message: 'Állomás sikeresen frissítve!' });
      } else {
        const docRef = await addDoc(collection(db, 'stations'), {
          ...dataToSave,
          createdAt: serverTimestamp()
        });
        console.log('✅ Új állomás létrehozva:', docRef.id);
        setToast({ type: 'success', message: 'Új állomás sikeresen létrehozva!' });
      }
      
      setShowStationModal(false);
      fetchStations();
    } catch (error) {
      console.error('❌ Hiba az állomás mentésekor:', error);
      setToast({ type: 'error', message: `Hiba a mentés során: ${error.message}` });
    }
  };

  // PROGRAM ACTIONS
  const handleCreateProgram = () => {
    setEditingProgram(null);
    setShowProgramModal(true);
  };

  const handleEditProgram = (program) => {
    setEditingProgram(program);
    setShowProgramModal(true);
  };

  const handleDeleteProgram = (program) => {
    setConfirmDialog({
      title: 'Program törlése',
      message: `Biztosan törölni szeretnéd a(z) "${program.title}" programot?`,
      onConfirm: async () => {
        try {
          await deleteDoc(doc(db, 'programs', program.id));
          setToast({ type: 'success', message: 'Program törölve!' });
          fetchPrograms();
        } catch (error) {
          setToast({ type: 'error', message: 'Hiba a törlés során' });
        }
      }
    });
  };

  const handleSaveProgram = async (programData) => {
    try {
      console.log('💾 Program mentése:', programData);
      
      if (editingProgram) {
        await updateDoc(doc(db, 'programs', editingProgram.id), programData);
        console.log('✅ Program frissítve:', editingProgram.id);
        setToast({ type: 'success', message: 'Program sikeresen frissítve!' });
      } else {
        const docRef = await addDoc(collection(db, 'programs'), {
          ...programData,
          createdAt: serverTimestamp()
        });
        console.log('✅ Új program létrehozva:', docRef.id);
        setToast({ type: 'success', message: 'Új program sikeresen létrehozva!' });
      }
      
      setShowProgramModal(false);
      fetchPrograms();
    } catch (error) {
      console.error('❌ Hiba a program mentésekor:', error);
      setToast({ type: 'error', message: `Hiba a mentés során: ${error.message}` });
    }
  };

  // TRIP ACTIONS
  const handleEditTrip = (trip) => {
    setEditingTrip(trip);
    setShowTripModal(true);
  };

  const handleSaveTrip = async (tripData) => {
    try {
      await updateDoc(doc(db, 'trips', editingTrip.id), tripData);
      setToast({ type: 'success', message: 'Túra frissítve!' });
      setShowTripModal(false);
      fetchTrips();
    } catch (error) {
      setToast({ type: 'error', message: 'Hiba a mentés során' });
    }
  };

  // USER ACTIONS
  const handleToggleAdmin = async (userId, currentStatus) => {
    try {
      await updateDoc(doc(db, 'users', userId), {
        isAdmin: !currentStatus
      });
      setToast({ 
        type: 'success', 
        message: `Admin jogosultság ${!currentStatus ? 'megadva' : 'elvéve'}!` 
      });
      fetchUsers();
    } catch (error) {
      setToast({ type: 'error', message: 'Hiba a jogosultság módosítása során' });
    }
  };

  // Helper komponens a túra térképhez statisztikákkal
  function TripMapWithStats({ trip, stations }) {
    const [routeInfo, setRouteInfo] = useState(null);

    return (
      <div className="trip-detail-card">
        {/* Túra info szekció */}
        <div className="trip-info-section">
          <div className="trip-header-row">
            <h3>{trip.name}</h3>
            <button
              className="btn btn-secondary"
              onClick={() => handleEditTrip(trip)}
            >
              ✏️ Szerkesztés
            </button>
          </div>
          
          <p className="trip-description">{trip.description}</p>
          
          <div className="trip-meta-grid">
            <div className="meta-card">
              <span className="meta-label">Távolság</span>
              <span className="meta-value">
                {routeInfo ? `${routeInfo.distance} km` : `${trip.distance} km`}
              </span>
            </div>
            <div className="meta-card">
              <span className="meta-label">Időtartam</span>
              <span className="meta-value">
                {routeInfo 
                  ? (routeInfo.time < 60 
                      ? `${routeInfo.time} perc` 
                      : `${Math.floor(routeInfo.time / 60)} óra ${routeInfo.time % 60} perc`)
                  : `${trip.duration} perc`}
              </span>
            </div>
            <div className="meta-card">
              <span className="meta-label">Állomások</span>
              <span className="meta-value">{stations.length} db</span>
            </div>
          </div>

          <div className="trip-status">
            <span className={`status-badge large ${trip.isActive ? 'active' : 'inactive'}`}>
              {trip.isActive ? '● Publikált' : '○ Vázlat'}
            </span>
          </div>

          {routeInfo && (
            <div className="route-info-badge">
              <span className="route-badge-icon">📊</span>
              <span className="route-badge-text">
                Valós útvonal adatok az OSRM alapján
              </span>
            </div>
          )}
        </div>

        {/* Térkép szekció */}
        <div className="trip-map-section">
          {stations.length < 2 ? (
            <div className="map-placeholder">
              <div className="placeholder-content">
                <span className="placeholder-icon">⚠️</span>
                <h4>Útvonal nem elérhető</h4>
                <p>Legalább 2 állomás szükséges az útvonal megjelenítéséhez</p>
              </div>
            </div>
          ) : (
            <TripMap 
              stations={stations} 
              tripName={trip.name}
              onRouteCalculated={setRouteInfo}
            />
          )}
        </div>
      </div>
    );
  }

  if (!user) {
    return (
      <div className="admin-panel">
        <div className="loading">Bejelentkezés szükséges...</div>
      </div>
    );
  }

  return (
    <div className="admin-panel">
      <header className="admin-header">
        <h1>🛠️ Admin Panel</h1>
        <p>Állomások, programok és túrák kezelése</p>
      </header>

      <div className="admin-tabs">
        <button
          className={`tab ${activeTab === 'stations' ? 'active' : ''}`}
          onClick={() => setActiveTab('stations')}
        >
          📍 Állomások
        </button>
        <button
          className={`tab ${activeTab === 'programs' ? 'active' : ''}`}
          onClick={() => setActiveTab('programs')}
        >
          🎪 Programok
        </button>
        <button
          className={`tab ${activeTab === 'trips' ? 'active' : ''}`}
          onClick={() => setActiveTab('trips')}
        >
          🗺️ Túrák
        </button>
        <button
          className={`tab ${activeTab === 'users' ? 'active' : ''}`}
          onClick={() => setActiveTab('users')}
        >
          👥 Felhasználók
        </button>
      </div>

      <div className="admin-content">
        {/* ÁLLOMÁSOK TAB */}
        {activeTab === 'stations' && (
          <div className="stations-section">
            <div className="section-header">
              <h2>Állomások kezelése</h2>
              <button className="btn btn-primary" onClick={handleCreateStation}>
                ➕ Új állomás
              </button>
            </div>

            {loading ? (
              <div className="loading">Betöltés...</div>
            ) : stations.length === 0 ? (
              <div className="empty-state">
                <p>Még nincsenek állomások. Hozz létre egyet!</p>
                <button className="btn btn-primary" onClick={handleCreateStation}>
                  ➕ Első állomás létrehozása
                </button>
              </div>
            ) : (
              <div className="data-table">
                <table>
                  <thead>
                    <tr>
                      <th>#</th>
                      <th>Név</th>
                      <th>Túra</th>
                      <th>Sorrend</th>
                      <th>Pont</th>
                      <th>QR kód</th>
                      <th>Aktív</th>
                      <th>Műveletek</th>
                    </tr>
                  </thead>
                  <tbody>
                    {stations.map((station, index) => (
                      <tr key={station.id}>
                        <td>{index + 1}</td>
                        <td>
                          <strong>{station.name}</strong>
                          <br />
                          <small className="text-muted">
                            {station.description?.substring(0, 50)}
                            {station.description?.length > 50 ? '...' : ''}
                          </small>
                        </td>
                        <td>
                          <span className="badge badge-info">{station.tripName}</span>
                        </td>
                        <td>
                          <input 
                            type="number" 
                            value={station.orderIndex || 0}
                            onChange={async (e) => {
                              try {
                                await updateDoc(doc(db, 'stations', station.id), { 
                                  orderIndex: parseInt(e.target.value) || 0 
                                });
                                fetchStations();
                              } catch (error) {
                                console.error('Hiba a sorrend mentésekor:', error);
                              }
                            }}
                            style={{width: '60px', padding: '4px 8px', textAlign: 'center' }}
                            className="order-input"
                          />
                        </td>
                        <td>
                          <strong>{station.points ?? 10}</strong>
                        </td>
                        <td>
                          {station.qrCode ? (
                            <span className="badge badge-success">✓ {station.qrCode}</span>
                          ) : (
                            <span className="badge badge-secondary">Nincs</span>
                          )}
                        </td>
                        <td>
                          <label className="toggle-switch">
                            <input 
                              type="checkbox" 
                              checked={station.isActive === true}
                              onChange={async (e) => {
                                const newStatus = e.target.checked;
                                
                                // Optimistic UI update
                                setStations(prevStations => 
                                  prevStations.map(s => 
                                    s.id === station.id 
                                      ? { ...s, isActive: newStatus }
                                      : s
                                  )
                                );

                                try {
                                  console.log(`🔄 Állomás ${station.name} státusz mentése Firestore-ba:`, newStatus);
                                  
                                  await updateDoc(doc(db, 'stations', station.id), { 
                                    isActive: newStatus,
                                    updatedAt: serverTimestamp()
                                  });
                                  
                                  console.log(`✅ Firestore frissítve: stations/${station.id} -> isActive: ${newStatus}`);
                                  
                                  setToast({ 
                                    type: 'success', 
                                    message: `Állomás ${newStatus ? 'aktiválva ✅' : 'deaktiválva ❌'} és mentve!` 
                                  });
                                  
                                  setTimeout(() => {
                                    fetchStations();
                                  }, 500);
                                  
                                } catch (error) {
                                  console.error('❌ Hiba a Firestore mentés során:', error);
                                  
                                  setStations(prevStations => 
                                    prevStations.map(s => 
                                      s.id === station.id 
                                        ? { ...s, isActive: !newStatus }
                                        : s
                                    )
                                  );
                                  
                                  setToast({ 
                                    type: 'error', 
                                    message: `Hiba a mentés során: ${error.message}` 
                                  });
                                }
                              }}
                            />
                            <span className="toggle-slider"></span>
                          </label>
                          <span className={`status-label-friendly ${station.isActive === true ? 'active' : 'inactive'}`}>
                            {station.isActive === true ? '✓ Elérhető' : '○ Rejtett'}
                          </span>
                        </td>
                        <td>
                          <div className="action-buttons">
                            <button
                              className="btn-icon btn-edit"
                              onClick={() => handleEditStation(station)}
                              title="Szerkesztés"
                            >
                              ✏️
                            </button>
                            <button
                              className="btn-icon btn-delete"
                              onClick={() => handleDeleteStation(station)}
                              title="Törlés"
                            >
                              🗑️
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}

        {/* PROGRAMOK TAB */}
        {activeTab === 'programs' && (
          <div className="programs-section">
            <div className="section-header">
              <h2>Programok kezelése</h2>
              <button className="btn btn-primary" onClick={handleCreateProgram}>
                ➕ Új program
              </button>
            </div>

            {loading ? (
              <div className="loading">Betöltés...</div>
            ) : programs.length === 0 ? (
              <div className="empty-state">
                <p>Még nincsenek programok. Hozz létre egyet!</p>
              </div>
            ) : (
              <div className="programs-grid">
                {programs.map(program => (
                  <div key={program.id} className="program-card">
                    {program.imageUrl && (
                      <div className="program-image">
                        <img src={program.imageUrl} alt={program.title} />
                      </div>
                    )}
                    <div className="program-content">
                      <div className="program-header">
                        <h3>{program.title}</h3>
                        <span className={`status-badge ${program.isActive ? 'active' : 'inactive'}`}>
                          {program.isActive ? '● Látható' : '○ Elrejtve'}
                        </span>
                      </div>
                      <p className="program-description">{program.description}</p>
                      <div className="program-meta">
                        <div className="meta-item">
                          <span className="meta-icon">📅</span>
                          <span>
                            {program.date 
                              ? new Date(program.date.seconds * 1000).toLocaleDateString('hu-HU', {
                                  year: 'numeric',
                                  month: 'long',
                                  day: 'numeric',
                                  hour: '2-digit',
                                  minute: '2-digit'
                                })
                              : 'Nincs dátum'}
                          </span>
                        </div>
                        <div className="meta-item">
                          <span className="meta-icon">📍</span>
                          <span>{program.location || 'Nincs helyszín'}</span>
                        </div>
                      </div>
                      <div className="program-actions">
                        <button
                          className="btn btn-secondary btn-sm"
                          onClick={() => handleEditProgram(program)}
                        >
                          ✏️ Szerkesztés
                        </button>
                        <button
                          className="btn btn-danger btn-sm"
                          onClick={() => handleDeleteProgram(program)}
                        >
                          🗑️ Törlés
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* TÚRÁK TAB */}
        {activeTab === 'trips' && (
          <div className="trips-section">
            <div className="section-header">
              <h2>🗺️ Túrák kezelése</h2>
            </div>

            {loading ? (
              <div className="loading">Betöltés...</div>
            ) : trips.length === 0 ? (
              <div className="empty-state">
                <p>Nincsenek túrák.</p>
              </div>
            ) : (
              <div className="trips-with-maps">
                {trips.map((trip) => {
                  const tripStations = stations.filter(s => s.tripId === trip.id)
                    .sort((a, b) => a.orderIndex - b.orderIndex);
                  
                  return (
                    <TripMapWithStats 
                      key={trip.id}
                      trip={trip}
                      stations={tripStations}
                    />
                  );
                })}
              </div>
            )}
          </div>
        )}

        {/* FELHASZNÁLÓK TAB */}
        {activeTab === 'users' && (
          <div className="users-section">
            <div className="section-header">
              <h2>Felhasználók kezelése</h2>
            </div>

            {loading ? (
              <div className="loading">Betöltés...</div>
            ) : users.length === 0 ? (
              <div className="empty-state">
                <p>Még nincsenek regisztrált felhasználók.</p>
              </div>
            ) : (
              <div className="data-table">
                <table>
                  <thead>
                    <tr>
                      <th>Név</th>
                      <th>Email</th>
                      <th>Regisztráció</th>
                      <th>Pontok</th>
                      <th>Teljesített túrák</th>
                      <th>Meglátogatott állomások</th>
                      <th>Admin</th>
                      <th>Műveletek</th>
                    </tr>
                  </thead>
                  <tbody>
                    {users.map(u => (
                      <tr key={u.id}>
                        <td>
                          <strong>{u.displayName || '-'}</strong>
                        </td>
                        <td>{u.email}</td>
                        <td>
                          {u.createdAt 
                            ? new Date(u.createdAt.seconds * 1000).toLocaleDateString('hu-HU')
                            : '-'}
                        </td>
                        <td>
                          <span style={{
                            background: '#667eea',
                            color: 'white',
                            padding: '4px 12px',
                            borderRadius: '12px',
                            fontWeight: 'bold',
                            fontSize: '14px'
                          }}>
                            ⭐ {u.points || 0}
                          </span>
                        </td>
                        <td>
                          <span className="badge badge-info">
                            {Array.isArray(u.completedTrips) ? u.completedTrips.length : 0} túra
                          </span>
                        </td>
                        <td>
                          <span className="badge badge-success">
                            {Array.isArray(u.visitedStations) ? u.visitedStations.length : 0} állomás
                          </span>
                        </td>
                        <td>
                          <span className={`status-badge ${u.isAdmin ? 'active' : 'inactive'}`}>
                            {u.isAdmin ? '★ Admin' : '● Felhasználó'}
                          </span>
                        </td>
                        <td>
                          <div className="action-buttons">
                            <button
                              className={`btn-icon ${u.isAdmin ? 'btn-warning' : 'btn-success'}`}
                              onClick={() => handleToggleAdmin(u.id, u.isAdmin)}
                              title={u.isAdmin ? 'Admin jog visszavonása' : 'Admin jog megadása'}
                            >
                              {u.isAdmin ? '⬇️' : '⬆️'}
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}
      </div>

      {/* MODALS */}
      {showStationModal && (
        <StationModal
          station={editingStation}
          trips={trips}
          onClose={() => setShowStationModal(false)}
          onSave={handleSaveStation}
        />
      )}

      {showProgramModal && (
        <ProgramModal
          program={editingProgram}
          onClose={() => setShowProgramModal(false)}
          onSave={handleSaveProgram}
        />
      )}

      {showTripModal && (
        <TripModal
          trip={editingTrip}
          onClose={() => setShowTripModal(false)}
          onSave={handleSaveTrip}
        />
      )}

      {confirmDialog && (
        <ConfirmDialog
          title={confirmDialog.title}
          message={confirmDialog.message}
          onClose={() => setConfirmDialog(null)}
          actions={[
            { label: 'Megerősítés', onClick: confirmDialog.onConfirm }
          ]}
        />
      )}

      {toast && (
        <Toast
          type={toast.type}
          message={toast.message}
          onClose={() => setToast(null)}
        />
      )}
    </div>
  );
}



