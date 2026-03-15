import React, { useState } from "react";
import { db } from "../firebaseConfig";
import { collection, addDoc, deleteDoc, getDocs, doc } from "firebase/firestore";
import "../styles/Content.css";
import ConfirmDialog from "../components/ConfirmDialog";

function SeedDatabase() {
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(false);
  const [stats, setStats] = useState(null);
  const [clearDialogOpen, setClearDialogOpen] = useState(false);

  const seedData = async () => {
    setLoading(true);
    setMessage("");
    setStats(null);

    try {
      let itemsAdded = 0;

      await addDoc(collection(db, "about"), {
        title: "Nagyvázsony",
        content: "Nagyvázsony egy történelmi település Veszprém megye szívében.",
        createdAt: new Date(),
      });
      itemsAdded++;

      const events = [
        { name: "Nyári Fesztivál", date: "2026-07-15", description: "Zenei és kulturális fesztivál", location: "Nagyvázsony központ" },
        { name: "Pünkösdi Ünnep", date: "2026-05-24", description: "Hagyományos pünkösdi fesztivál", location: "Egyházi terület" },
        { name: "Főzési Verseny", date: "2026-09-12", description: "Helyi ételkészítési verseny", location: "Közösségi ház" },
        { name: "Karácsony Vásár", date: "2026-12-05", description: "Karácsonyi vásári készülődés", location: "Nagyvázsony tér" },
        { name: "Tavaszi Séta", date: "2026-04-19", description: "Közösségi tavaszi természetjárás", location: "Kirándulási útvonal" },
      ];

      for (const event of events) {
        await addDoc(collection(db, "events"), { ...event, createdAt: new Date() });
        itemsAdded++;
      }

      const accommodations = [
        { name: "Hotel Spa Nagyvázsony", type: "hotel", pricePerNight: "28000-45000 Ft", capacity: 50, amenities: ["WiFi", "Konyha", "Wellness"], description: "Luxus hotel spa szolgáltatásokkal" },
        { name: "Vendégház Nagyvázsony", type: "guesthouse", pricePerNight: "12000-18000 Ft", capacity: 20, amenities: ["WiFi", "Konyha", "Közös area"], description: "Hangulatos vendégház" },
        { name: "Apartmanok Nagyvázsony", type: "apartment", pricePerNight: "15000-35000 Ft", capacity: 40, amenities: ["WiFi", "Terasz", "Konyha"], description: "Apartmanok" },
        { name: "Kemping Nagyvázsony", type: "campsite", pricePerNight: "3000-8000 Ft", capacity: 100, amenities: ["Vízvezeték", "Elektromosság"], description: "Kempingezésre alkalmas terület" },
      ];

      for (const acc of accommodations) {
        await addDoc(collection(db, "accommodations"), { ...acc, createdAt: new Date() });
        itemsAdded++;
      }

      const restaurants = [
        { name: "Magyar Konyha", type: "hungarian", cuisine: "Magyar", priceRange: "2000-4000 Ft", description: "Hagyományos magyar ételek" },
        { name: "Hali Étterem", type: "fish", cuisine: "Halfélékre specializált", priceRange: "3000-6000 Ft", description: "Friss halételek" },
        { name: "Kávézó Nagyvázsony", type: "cafe", cuisine: "Kávé és desszertek", priceRange: "1000-2000 Ft", description: "Hangulatos kávézó" },
        { name: "Pizzeria Napoli", type: "pizzeria", cuisine: "Olasz", priceRange: "2000-3500 Ft", description: "Autentikus olasz pizza" },
        { name: "Fagylaltzó Éden", type: "icecream", cuisine: "Fagylalt és smoothie", priceRange: "500-1500 Ft", description: "Készült fagylalt" },
        { name: "Bár Lounge", type: "bar", cuisine: "Koktél és ital", priceRange: "1500-3000 Ft", description: "Éjszakai szórakozás" },
      ];

      for (const rest of restaurants) {
        await addDoc(collection(db, "restaurants"), { ...rest, createdAt: new Date() });
        itemsAdded++;
      }

      const trips = [
        { name: "Központi Körkörút", description: "Nagyvázsony szívét feltáró túra", distance: 3.2, duration: "45 perc", isActive: true },
        { name: "Sárvár Kerékpár Túra", description: "Kerékpáros túra Sárvár közvetlenségig", distance: 8.5, duration: "75 perc", isActive: true },
        { name: "Erdei Ösvény", description: "Erdei szépségek közötti séta", distance: 6.3, duration: "105 perc", isActive: true },
      ];

      for (const trip of trips) {
        await addDoc(collection(db, "trips"), { ...trip, createdAt: new Date() });
        itemsAdded++;
      }

      const stations = [
        { name: "Nagyvázsony Fölia", description: "Köztéri szobor és emlékhely", latitude: 47.067, longitude: 17.711, qrCode: "GV-001", tripId: "" },
        { name: "Evangélikus Templom", description: "Történelmi templom", latitude: 47.065, longitude: 17.712, qrCode: "GV-002", tripId: "" },
        { name: "Városháza", description: "Közigazgatási központ", latitude: 47.064, longitude: 17.710, qrCode: "GV-003", tripId: "" },
        { name: "Piactér", description: "Nagyvázsony szívpontja", latitude: 47.066, longitude: 17.713, qrCode: "GV-004", tripId: "" },
        { name: "Közpark", description: "Város zöld tüdeje", latitude: 47.068, longitude: 17.714, qrCode: "GV-005", tripId: "" },
        { name: "Múzeum", description: "Nagyvázsony helytörténeti múzeum", latitude: 47.063, longitude: 17.709, qrCode: "GV-006", tripId: "" },
        { name: "Könyvtár", description: "Közösségi könyvtár", latitude: 47.062, longitude: 17.711, qrCode: "GV-007", tripId: "" },
        { name: "Sport pályák", description: "Sporton túrázók számára", latitude: 47.069, longitude: 17.715, qrCode: "GV-008", tripId: "" },
        { name: "Vízi part", description: "Nagyvázsony vízi part área", latitude: 47.070, longitude: 17.716, qrCode: "GV-009", tripId: "" },
        { name: "Erdei ösvény kezdet", description: "Erdei túra kezdőpontja", latitude: 47.071, longitude: 17.717, qrCode: "GV-010", tripId: "" },
        { name: "Kilátópont", description: "Nagyvázsony panoráma kilátása", latitude: 47.072, longitude: 17.718, qrCode: "GV-011", tripId: "" },
        { name: "Város vége", description: "Városhatárok melletti pont", latitude: 47.073, longitude: 17.719, qrCode: "GV-012", tripId: "" },
      ];

      for (const station of stations) {
        await addDoc(collection(db, "stations"), { ...station, createdAt: new Date() });
        itemsAdded++;
      }

      setMessage(`✅ Sikeresen feltöltöttük az adatbázist: ${itemsAdded} elem hozzáadva`);
      setStats({ about: 1, events: 5, accommodations: 4, restaurants: 6, trips: 3, stations: 12, total: itemsAdded });
    } catch (error) {
      setMessage(`❌ Hiba történt: ${error.message}`);
    } finally {
      setLoading(false);
    }
  };

  const clearDatabase = async () => {
    setClearDialogOpen(false);
    setLoading(true);
    setMessage("");
    setStats(null);

    try {
      const collections_to_clear = ["about", "contact", "events", "accommodations", "restaurants", "trips", "stations"];
      let itemsDeleted = 0;

      for (const collectionName of collections_to_clear) {
        const snapshot = await getDocs(collection(db, collectionName));
        for (const docSnap of snapshot.docs) {
          await deleteDoc(doc(db, collectionName, docSnap.id));
          itemsDeleted++;
        }
      }

      setMessage(`✅ Sikeresen töröltük az adatbázist: ${itemsDeleted} elem törölve`);
      setStats({ total: 0 });
    } catch (error) {
      setMessage(`❌ Hiba történt: ${error.message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="content-page">
      <div className="page-header">
        <h1>🗄️ Adatbázis Kezelése</h1>
        <p>Adatbázis feltöltés és kezelés</p>
      </div>

      <div className="seed-actions">
        <button className="btn-primary" onClick={seedData} disabled={loading}>
          {loading ? "Feldolgozás..." : "📊 Adatbázis Feltöltése"}
        </button>
        <button className="btn-secondary" onClick={() => setClearDialogOpen(true)} disabled={loading}>
          {loading ? "Feldolgozás..." : "🗑️ Mindent Töröl"}
        </button>
      </div>

      {message && (
        <div className={`message ${message.includes("❌") ? "error" : "success"}`}>
          <p>{message}</p>
        </div>
      )}

      {stats && (
        <div className="stats-grid">
          {stats.about !== undefined && <div className="stat-card"><strong>Történelem</strong><span>{stats.about}</span></div>}
          {stats.events !== undefined && <div className="stat-card"><strong>Rendezvények</strong><span>{stats.events}</span></div>}
          {stats.accommodations !== undefined && <div className="stat-card"><strong>Szállások</strong><span>{stats.accommodations}</span></div>}
          {stats.restaurants !== undefined && <div className="stat-card"><strong>Vendéglátás</strong><span>{stats.restaurants}</span></div>}
          {stats.trips !== undefined && <div className="stat-card"><strong>Túrák</strong><span>{stats.trips}</span></div>}
          {stats.stations !== undefined && <div className="stat-card"><strong>Állomások</strong><span>{stats.stations}</span></div>}
          <div className="stat-card" style={{gridColumn: "1 / -1", fontWeight: "bold"}}>
            <strong>Összes elem: {stats.total}</strong>
          </div>
        </div>
      )}
          <ConfirmDialog
        open={clearDialogOpen}
        title="Teljes adatbázis törlése"
        message="Biztosan töröljük az ÖSSZES adatot az adatbázisból?"
        confirmText="Mindent törlök"
        onClose={() => setClearDialogOpen(false)}
        onConfirm={clearDatabase}
      />
    </div>
  );
}

export default SeedDatabase;


