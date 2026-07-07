import React, { useState, useEffect } from "react";
import { db } from "../firebaseConfig";
import { collection, getDocs, doc, updateDoc } from "firebase/firestore";
import Snackbar from "@mui/material/Snackbar";
import Alert from "@mui/material/Alert";
import "../styles/Users.css";
import StateCard from "../components/StateCard";
import ConfirmDialog from "../components/ConfirmDialog";
import { useAdminAuth } from "../context/AdminAuthContext";
import { buildCsv, downloadCsv } from "../utils/exportCsv";

const formatDate = (value) => {
  if (!value) return "N/A";
  try {
    const date = value?.toDate ? value.toDate() : new Date(value);
    if (Number.isNaN(date.getTime())) return "N/A";
    return date.toLocaleString("hu-HU");
  } catch {
    return "N/A";
  }
};

function Users() {
  const { userEmail: currentAdminEmail } = useAdminAuth();
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [roleDialog, setRoleDialog] = useState({ open: false, user: null });
  const [savingRoleId, setSavingRoleId] = useState(null);
  const [snack, setSnack] = useState({ open: false, message: "", severity: "success" });
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const PAGE_SIZE = 50;
  async function fetchUsers() {
    try {
      setLoading(true);
      setError(null);

      const [usersSnapshot, progressSnapshot] = await Promise.all([
        getDocs(collection(db, "users")),
        getDocs(collection(db, "user_progress")),
      ]);

      const progressRows = await Promise.all(
        progressSnapshot.docs.map(async (progressDoc) => {
          const progressData = progressDoc.data();

          let completedStations = 0;
          if (Array.isArray(progressData.completedStations)) {
            completedStations = progressData.completedStations.length;
          } else {
            // Avoid N+1 subcollection query: use the denormalized count field if available
            completedStations = Number(progressData.completedStationsCount || 0);
          }

          const totalStations = Number(progressData.totalStations || 0);
          const progress =
            totalStations > 0
              ? Math.round((completedStations / totalStations) * 100)
              : 0;

          return {
            id: progressDoc.id,
            userId: progressData.userId || progressDoc.id,
            uid: progressData.userId || progressDoc.id,
            email: progressData.email || "",
            userName: progressData.userName || "Ismeretlen",
            role: "user",
            tripId: progressData.tripId || "N/A",
            completedStations,
            totalStations,
            progress,
            points: Number(progressData.totalPoints ?? progressData.points ?? 0),
            lastUpdated: progressData.lastUpdated || null,
            createdAt: progressData.createdAt || null,
            hasAccount: false,
          };
        })
      );

      const combinedByKey = new Map();

      usersSnapshot.docs.forEach((userDoc) => {
        const userData = userDoc.data();
        const docId = userDoc.id;
        const email = (userData.email || (docId.includes("@") ? docId : "")).trim();
        const uid = (userData.uid || userData.userId || "").trim();
        const key = uid || email || docId;

        combinedByKey.set(key, {
          id: docId,
          userId: uid || docId,
          uid,
          email,
          userName: userData.name || userData.userName || email || "Ismeretlen",
          role: userData.role || "user",
          tripId: "N/A",
          completedStations: 0,
          totalStations: 0,
          progress: 0,
          points: 0,
          lastUpdated: userData.lastUpdated || null,
          createdAt: userData.createdAt || null,
          hasAccount: true,
        });
      });

      progressRows.forEach((progressUser) => {
        const possibleKeys = [
          progressUser.uid,
          progressUser.email,
          progressUser.id,
        ].filter(Boolean);

        const foundKey = possibleKeys.find((item) => combinedByKey.has(item));

        if (!foundKey) {
          const key = progressUser.uid || progressUser.email || progressUser.id;
          combinedByKey.set(key, {
            ...progressUser,
            role: "user",
            userName: progressUser.userName || progressUser.email || "Ismeretlen",
          });
          return;
        }

        const existing = combinedByKey.get(foundKey);
        combinedByKey.set(foundKey, {
          ...existing,
          ...progressUser,
          id: existing.id || progressUser.id,
          role: existing.role || progressUser.role || "user",
          userName:
            existing.userName !== "Ismeretlen"
              ? existing.userName
              : progressUser.userName,
          email: existing.email || progressUser.email,
          uid: existing.uid || progressUser.uid,
          hasAccount: existing.hasAccount || progressUser.hasAccount,
        });
      });

      const usersData = [...combinedByKey.values()].sort((a, b) => {
        if (b.points !== a.points) return b.points - a.points;
        return (a.email || a.userName).localeCompare(b.email || b.userName, "hu");
      });

      setUsers(usersData);
    } catch {
      setError("Nem sikerült betölteni az adatokat");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    const timer = setTimeout(() => {
      void fetchUsers();
    }, 0);

    return () => clearTimeout(timer);
  }, []);

  const isCurrentAdmin = (user) =>
    currentAdminEmail &&
    user.email &&
    user.email.toLowerCase() === currentAdminEmail.toLowerCase();

  const handleExportCsv = () => {
    const columns = [
      { key: "rank", label: "Rang" },
      { key: "userName", label: "Név" },
      { key: "email", label: "Email" },
      { key: "role", label: "Szerepkör", format: (v) => (v === "admin" ? "Admin" : "Felhasználó") },
      { key: "points", label: "Pont" },
      { key: "completedStations", label: "Teljesített állomások" },
      { key: "totalStations", label: "Összes állomás" },
      { key: "progress", label: "Haladás (%)" },
      { key: "lastUpdated", label: "Utolsó aktivitás", format: (v) => formatDate(v) },
    ];
    const rows = users.map((user, index) => ({ ...user, rank: index + 1 }));
    const today = new Date().toISOString().slice(0, 10);
    downloadCsv(`felhasznalok_${today}.csv`, buildCsv(rows, columns));
    setSnack({ open: true, severity: "success", message: `${users.length} felhasználó exportálva CSV-be.` });
  };

  const confirmRoleChange = async () => {
    const user = roleDialog.user;
    setRoleDialog({ open: false, user: null });
    if (!user?.id) return;

    const newRole = user.role === "admin" ? "user" : "admin";
    setSavingRoleId(user.id);
    try {
      await updateDoc(doc(db, "users", user.id), { role: newRole });
      setUsers((prev) =>
        prev.map((u) => (u.id === user.id ? { ...u, role: newRole } : u))
      );
      setSnack({
        open: true,
        severity: "success",
        message:
          newRole === "admin"
            ? `${user.userName} mostantól admin.`
            : `${user.userName} admin jogát visszavontuk.`,
      });
    } catch (err) {
      setSnack({ open: true, severity: "error", message: "Hiba a szerepkör mentésekor: " + err.message });
    } finally {
      setSavingRoleId(null);
    }
  };

  if (loading) {
    return (
      <div className="users-page">
        <div className="page-header">
          <h1>👥 Felhasználók</h1>
          <p>Regisztrált fiókok és haladásuk áttekintése</p>
        </div>
        <StateCard
          variant="loading"
          icon="⏳"
          title="Felhasználók betöltése..."
          description="A rendszer összegyűjti a users és user_progress adatait."
        />
      </div>
    );
  }

  if (error) {
    return (
      <div className="users-page">
        <div className="page-header">
          <h1>👥 Felhasználók</h1>
          <p>Regisztrált fiókok és haladásuk áttekintése</p>
        </div>
        <StateCard
          icon="⚠️"
          title="Nem sikerült betölteni a felhasználókat"
          description={error}
          actionLabel="Újrapróbálás"
          onAction={() => {
            void fetchUsers();
          }}
        />
      </div>
    );
  }

  const getRankBadge = (index) => {
    if (index === 0) return "🥇";
    if (index === 1) return "🥈";
    if (index === 2) return "🥉";
    return "#" + (index + 1);
  };

  const adminCount = users.filter((item) => item.role === "admin").length;
  // reduce (not Math.max(...spread)) so this stays safe with thousands of users.
  const maxPoints = users.reduce((max, u) => (u.points > max ? u.points : max), 0);

  // Search + pagination keep the ranking responsive even with thousands of users:
  // only one page worth of rows is ever rendered into the DOM.
  const q = search.trim().toLowerCase();
  const filteredUsers = q
    ? users.filter(
        (u) =>
          (u.userName && u.userName.toLowerCase().includes(q)) ||
          (u.email && u.email.toLowerCase().includes(q))
      )
    : users;
  const totalPages = Math.max(1, Math.ceil(filteredUsers.length / PAGE_SIZE));
  const safePage = Math.min(page, totalPages);
  const pageStart = (safePage - 1) * PAGE_SIZE;
  const pagedUsers = filteredUsers.slice(pageStart, pageStart + PAGE_SIZE);

  const onSearchChange = (value) => {
    setSearch(value);
    setPage(1);
  };

  return (
    <div className="users-page">
      <div className="page-header">
        <h1>👥 Felhasználók</h1>
        <p>Regisztrált fiókok és haladásuk áttekintése</p>
      </div>

      <div className="users-stats">
        <div className="stat-box">
          <div className="stat-number">{users.length}</div>
          <div className="stat-label">Összes felhasználó</div>
        </div>
        <div className="stat-box">
          <div className="stat-number">{adminCount}</div>
          <div className="stat-label">Admin</div>
        </div>
        <div className="stat-box">
          <div className="stat-number">{maxPoints}</div>
          <div className="stat-label">Legtöbb pont</div>
        </div>
      </div>

      {users.length === 0 ? (
        <StateCard
          icon="👥"
          title="Nincsenek még felhasználók"
          description="Az alkalmazás még nem kapott felhasználói adatot. Amint érkezik új rekord, itt jelenik meg a ranglista."
        />
      ) : (
        <>
          <div className="users-toolbar">
            <input
              className="users-search"
              type="search"
              placeholder="🔍 Keresés név vagy email alapján..."
              value={search}
              onChange={(e) => onSearchChange(e.target.value)}
            />
            <button type="button" className="users-export-btn" onClick={handleExportCsv}>
              ⬇ CSV export ({users.length})
            </button>
          </div>

          {filteredUsers.length === 0 ? (
            <StateCard
              variant="empty"
              icon="🔎"
              title="Nincs találat"
              description="Próbálj másik kulcsszót, vagy töröld a keresést."
              actionLabel="Keresés törlése"
              onAction={() => onSearchChange("")}
            />
          ) : (
            <>
              <div className="users-ranking">
                <div className="users-header">
                  <div className="rank-col">Rang</div>
                  <div className="name-col">Felhasználó</div>
                  <div className="role-col">Szerepkör</div>
                  <div className="points-col">Pontok</div>
                  <div className="progress-col">Haladás</div>
                  <div className="activity-col">Utolsó aktivitás</div>
                </div>

                {pagedUsers.map((user, localIndex) => {
                  const index = pageStart + localIndex;
                  return (
                    <div
                      key={user.id || user.userId}
                      className={`user-row${index < 3 ? " top" : ""}`}
                    >
                      <div className="rank-col">
                        <div className="rank-badge">{getRankBadge(index)}</div>
                      </div>

                      <div className="name-col">
                        <strong title={user.uid ? `uid: ${user.uid}` : undefined}>
                          {user.userName}
                        </strong>
                        <small>{user.email || "Nincs email"}</small>
                      </div>

                      <div className="role-col">
                        <span className={`role-badge ${user.role === "admin" ? "admin" : "user"}`}>
                          {user.role === "admin" ? "Admin" : "Felhasználó"}
                        </span>
                        {user.hasAccount && (
                          <button
                            type="button"
                            className="role-toggle-btn"
                            disabled={isCurrentAdmin(user) || savingRoleId === user.id}
                            title={isCurrentAdmin(user) ? "A saját szerepköröd nem módosíthatod" : ""}
                            onClick={() => setRoleDialog({ open: true, user })}
                          >
                            {savingRoleId === user.id
                              ? "Mentés…"
                              : user.role === "admin"
                                ? "Admin jog elvétele"
                                : "Adminná tesz"}
                          </button>
                        )}
                      </div>

                      <div className="points-col">
                        <span className="points-badge">{user.points} pont</span>
                      </div>

                      <div className="progress-col">
                        <div className="progress-bar">
                          <div
                            className="progress-fill"
                            style={{ width: `${Math.max(0, Math.min(100, user.progress))}%` }}
                          ></div>
                        </div>
                        <span className="progress-text">
                          {user.completedStations}/{user.totalStations || "?"} állomás · {user.progress}%
                        </span>
                      </div>

                      <div className="activity-col" title={`doc: ${user.id || "N/A"}`}>
                        {formatDate(user.lastUpdated)}
                      </div>
                    </div>
                  );
                })}
              </div>

              {totalPages > 1 && (
                <div className="users-pagination">
                  <button
                    type="button"
                    className="users-page-btn"
                    disabled={safePage <= 1}
                    onClick={() => setPage(safePage - 1)}
                  >
                    ← Előző
                  </button>
                  <span className="users-page-info">
                    {safePage} / {totalPages} oldal · {filteredUsers.length} felhasználó
                  </span>
                  <button
                    type="button"
                    className="users-page-btn"
                    disabled={safePage >= totalPages}
                    onClick={() => setPage(safePage + 1)}
                  >
                    Következő →
                  </button>
                </div>
              )}
            </>
          )}
        </>
      )}

      <ConfirmDialog
        open={roleDialog.open}
        title={
          roleDialog.user?.role === "admin"
            ? "Admin jog visszavonása"
            : "Admin jog adása"
        }
        message={
          roleDialog.user
            ? roleDialog.user.role === "admin"
              ? `Biztosan visszavonod ${roleDialog.user.userName} admin jogát? Ezután már nem fér hozzá az adminfelülethez.`
              : `Biztosan admin jogot adsz ${roleDialog.user.userName} felhasználónak? Teljes hozzáférést kap az adminfelülethez.`
            : ""
        }
        confirmText={
          roleDialog.user?.role === "admin" ? "Visszavonás" : "Admin jog adása"
        }
        onClose={() => setRoleDialog({ open: false, user: null })}
        onConfirm={confirmRoleChange}
      />

      <Snackbar
        open={snack.open}
        autoHideDuration={4000}
        onClose={() => setSnack((s) => ({ ...s, open: false }))}
        anchorOrigin={{ vertical: "bottom", horizontal: "center" }}
      >
        <Alert
          severity={snack.severity}
          onClose={() => setSnack((s) => ({ ...s, open: false }))}
          sx={{ width: "100%" }}
        >
          {snack.message}
        </Alert>
      </Snackbar>
    </div>
  );
}

export default Users;


