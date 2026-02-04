import React, { useState, useEffect } from 'react';
import { db } from '../firebaseConfig';
import { collection, getDocs } from 'firebase/firestore';
import '../styles/Users.css';

function Users() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchUsers();
  }, []);

  const fetchUsers = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const usersSnapshot = await getDocs(collection(db, 'user_progress'));
      const usersData = await Promise.all(
        usersSnapshot.docs.map(async (doc) => {
          const userData = doc.data();
          
          // Calculate progress
          const completedStations = userData.completedStations?.length || 0;
          const totalStations = userData.totalStations || 0;
          const progress = totalStations > 0 ? Math.round((completedStations / totalStations) * 100) : 0;

          return {
            id: doc.id,
            userId: userData.userId || doc.id,
            tripId: userData.tripId || 'N/A',
            completedStations,
            totalStations,
            progress,
            lastUpdated: userData.lastUpdated?.toDate?.() || new Date(),
          };
        })
      );

      setUsers(usersData);
    } catch (err) {
      console.error('Hiba a felhasználók betöltésekor:', err);
      setError('Nem sikerült betölteni a felhasználókat');
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="users">
        <h1>Felhasználók haladása</h1>
        <p>Betöltés...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="users">
        <h1>Felhasználók haladása</h1>
        <p className="error">{error}</p>
      </div>
    );
  }

  return (
    <div className="users">
      <h1>Felhasználók haladása</h1>

      {users.length === 0 ? (
        <p>Még nincsenek felhasználók az adatbázisban.</p>
      ) : (
        <div className="users-list">
          {users.map(user => (
            <div key={user.id} className="user-item">
              <div className="user-header">
                <h3>👤 {user.userId}</h3>
                <span className="user-trip">🚶 Túra: {user.tripId}</span>
              </div>
              <div className="user-progress">
                <div className="progress-info">
                  <span>Haladás: {user.completedStations}/{user.totalStations} állomás</span>
                  <span className="progress-percentage">{user.progress}%</span>
                </div>
                <div className="progress-bar">
                  <div 
                    className="progress-fill" 
                    style={{ width: `${user.progress}%` }}
                  ></div>
                </div>
              </div>
              <div className="user-meta">
                <span>🕒 Utolsó frissítés: {user.lastUpdated.toLocaleString('hu-HU')}</span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default Users;
