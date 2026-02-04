import React, { useEffect, useState } from 'react';
import { MapContainer, TileLayer, Marker, Popup, Polyline } from 'react-leaflet';
import L from 'leaflet';

export const TripMap = ({ stations, tripName, onRouteCalculated }) => {
  const [routeCoordinates, setRouteCoordinates] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (stations.length < 2) return;

    const fetchRoute = async () => {
      setLoading(true);
      try {
        // Koordináták formázása az OSRM API-hoz
        const coords = stations.map(s => {
          const lng = s.location._long || s.location.longitude;
          const lat = s.location._lat || s.location.latitude;
          return `${lng},${lat}`;
        }).join(';');

        // OSRM API hívás (gyalogos útvonal)
        const response = await fetch(
          `https://router.project-osrm.org/route/v1/foot/${coords}?overview=full&geometries=geojson`
        );
        
        const data = await response.json();
        
        if (data.routes && data.routes[0]) {
          // GeoJSON koordináták konvertálása Leaflet formátumra
          const coordinates = data.routes[0].geometry.coordinates.map(coord => [coord[1], coord[0]]);
          setRouteCoordinates(coordinates);

          // Útvonal statisztikák kiszámítása TÚRÁZÓKHOZ
          const distance = (data.routes[0].distance / 1000).toFixed(2); // km
          
          // Túrázó sebesség: 4 km/h (reális túrázás)
          // + 5 perc/km pihenők és magasság kompenzáció
          const baseTime = (parseFloat(distance) / 4) * 60; // perc
          const breaksTime = parseFloat(distance) * 5; // 5 perc/km
          const totalTime = Math.round(baseTime + breaksTime);

          if (onRouteCalculated) {
            onRouteCalculated({ distance, time: totalTime });
          }
        }
      } catch (error) {
        console.error('Útvonal lekérési hiba:', error);
        // Fallback: egyenes vonalak
        const fallback = stations.map(s => [
          s.location._lat || s.location.latitude,
          s.location._long || s.location.longitude
        ]);
        setRouteCoordinates(fallback);
      } finally {
        setLoading(false);
      }
    };

    fetchRoute();
  }, [stations, onRouteCalculated]);

  if (stations.length === 0) return null;

  const center = [
    stations[0].location._lat || stations[0].location.latitude,
    stations[0].location._long || stations[0].location.longitude
  ];

  const createNumberIcon = (number) => {
    return L.divIcon({
      html: `<div style="
        background: linear-gradient(135deg, #667eea, #764ba2);
        color: white;
        width: 36px;
        height: 36px;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-weight: bold;
        border: 3px solid white;
        box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        font-size: 16px;
      ">${number}</div>`,
      iconSize: [36, 36],
      iconAnchor: [18, 18],
      popupAnchor: [0, -18]
    });
  };

  return (
    <div style={{ 
      height: '100%',
      width: '100%',
      minHeight: '450px',
      borderRadius: '12px', 
      overflow: 'hidden', 
      border: '2px solid #e9edf4',
      boxShadow: '0 4px 16px rgba(0,0,0,0.1)',
      position: 'relative'
    }}>
      {loading && (
        <div style={{
          position: 'absolute',
          top: '10px',
          right: '10px',
          background: 'white',
          padding: '8px 12px',
          borderRadius: '8px',
          zIndex: 1000,
          boxShadow: '0 2px 8px rgba(0,0,0,0.1)',
          fontSize: '12px',
          fontWeight: 'bold',
          color: '#667eea'
        }}>
          🔄 Útvonal betöltése...
        </div>
      )}
      
      <MapContainer 
        center={center} 
        zoom={14} 
        style={{ height: '100%', width: '100%' }}
        scrollWheelZoom={true}
      >
        <TileLayer
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          attribution='&copy; OpenStreetMap contributors'
        />

        {/* Útvonal vonal - valós út mentén */}
        {routeCoordinates.length > 0 && (
          <Polyline
            positions={routeCoordinates}
            pathOptions={{
              color: '#667eea',
              weight: 5,
              opacity: 0.8,
              lineCap: 'round',
              lineJoin: 'round'
            }}
          />
        )}

        {/* Állomás marker-ek */}
        {stations.map((station, index) => (
          <Marker
            key={station.id}
            position={[
              station.location._lat || station.location.latitude,
              station.location._long || station.location.longitude
            ]}
            icon={createNumberIcon(index + 1)}
          >
            <Popup>
              <div style={{ textAlign: 'center' }}>
                <strong style={{ fontSize: '14px' }}>{station.name}</strong>
                <br />
                <small style={{ color: '#666' }}>
                  Állomás #{index + 1}
                </small>
                {station.qrCode && (
                  <>
                    <br />
                    <small style={{ color: '#667eea' }}>
                      🔲 {station.qrCode}
                    </small>
                  </>
                )}
              </div>
            </Popup>
          </Marker>
        ))}
      </MapContainer>
    </div>
  );
};
