import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { collection, query, where, getDocs } from 'firebase/firestore';
import { db } from '../firebase';
import { useAppStore } from '../store/appStore';
import { Skeleton } from '../components/Skeleton';
import { Toast } from '../components/Toast';
import '../styles/HomePage.css';

const getPlaceholderImage = (name) => {
  return `https://placehold.co/400x300/667eea/ffffff?text=${encodeURIComponent(name)}`;
};

export default function HomePage() {
  const { user } = useAppStore();
  const [trips, setTrips] = useState([]);
  const [programs, setPrograms] = useState([]);
  const [loading, setLoading] = useState(true);
  const [toast, setToast] = useState(null);

  useEffect(() => {
    const fetchData = async () => {
      try {
        setLoading(true);

        // Túrák betöltése
        const tripsQuery = query(
          collection(db, 'trips'),
          where('isActive', '==', true)
        );
        const tripsSnapshot = await getDocs(tripsQuery);
        const tripsData = tripsSnapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data()
        }));
        setTrips(tripsData);

        // Programok betöltése
        const programsQuery = query(
          collection(db, 'programs'),
          where('isActive', '==', true)
        );
        const programsSnapshot = await getDocs(programsQuery);
        const programsData = programsSnapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data()
        }));
        setPrograms(programsData.sort((a, b) => {
          if (!a.date || !b.date) return 0;
          return b.date.seconds - a.date.seconds;
        }));

      } catch (error) {
        console.error('Hiba az adatok betöltésekor:', error);
        setToast({
          type: 'error',
          message: 'Nem sikerült betölteni az adatokat'
        });
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, []);

  return (
    <div className="home-page">
      {/* HERO SECTION */}
      <section className="hero-minimal">
        <div className="hero-content">
          <h1 className="hero-title">🏰 Fedezd fel Nagyvázsonyt</h1>
          <p className="hero-subtitle">Interaktív túrák és programok a történelmi várfalak között</p>
          {user?.isAdmin && (
            <div className="hero-actions">
              <Link to="/admin" className="btn btn-admin-hero">
                ⚙️ Admin Panel
              </Link>
            </div>
          )}
        </div>
      </section>

      <div className="content-wrapper">
        {/* TÚRÁK SZEKCIÓ */}
        <section className="section-trips">
          <div className="section-header-minimal">
            <h2>🗺️ Túrák</h2>
          </div>

          {loading ? (
            <div className="trips-grid-minimal">
              {[1, 2].map(i => (
                <Skeleton key={i} type="card" />
              ))}
            </div>
          ) : trips.length === 0 ? (
            <div className="empty-minimal">
              <p>Jelenleg nincsenek elérhető túrák.</p>
            </div>
          ) : (
            <div className="trips-grid-minimal">
              {trips.map(trail => (
                <Link
                  key={trail.id}
                  to={`/trail/${trail.id}`}
                  className="trip-card-minimal"
                >
                  <div className="trip-card-image">
                    <img
                      src={trail.imageUrl || getPlaceholderImage(trail.name)}
                      alt={trail.name}
                      onError={(e) => {
                        e.target.src = getPlaceholderImage(trail.name);
                      }}
                    />
                  </div>

                  <div className="trip-card-body">
                    <h3>{trail.name}</h3>
                    <p>{trail.description}</p>

                    <div className="trip-meta-minimal">
                      <span>⏱️ {trail.duration || 'N/A'} perc</span>
                      <span>📍 {trail.distance || 'N/A'} km</span>
                    </div>

                    <div className="trip-cta">
                      Indulás →
                    </div>
                  </div>
                </Link>
              ))}
            </div>
          )}
        </section>

        {/* PROGRAMOK SZEKCIÓ */}
        <section className="section-programs">
          <div className="section-header-minimal">
            <h2>🎪 Programok</h2>
          </div>

          {loading ? (
            <div className="programs-grid-minimal">
              {[1, 2, 3].map(i => (
                <Skeleton key={i} type="card" />
              ))}
            </div>
          ) : programs.length === 0 ? (
            <div className="empty-minimal">
              <p>Jelenleg nincsenek bejelentett programok.</p>
            </div>
          ) : (
            <div className="programs-grid-minimal">
              {programs.map(program => (
                <div key={program.id} className="program-card-minimal">
                  {program.imageUrl && (
                    <div className="program-card-image">
                      <img src={program.imageUrl} alt={program.title} />
                    </div>
                  )}

                  <div className="program-card-body">
                    <h3>{program.title}</h3>
                    <p>{program.description}</p>

                    <div className="program-info-minimal">
                      <div className="info-row">
                        <span className="info-icon">📅</span>
                        <span>
                          {program.date 
                            ? new Date(program.date.seconds * 1000).toLocaleDateString('hu-HU', {
                                year: 'numeric',
                                month: 'long',
                                day: 'numeric',
                                hour: '2-digit',
                                minute: '2-digit'
                              })
                            : 'Dátum nincs megadva'}
                        </span>
                      </div>
                      <div className="info-row">
                        <span className="info-icon">📍</span>
                        <span>{program.location || 'Helyszín nincs megadva'}</span>
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>
      </div>

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
