import React, { useEffect, useMemo, useState } from "react";
import { db, functions } from "../firebaseConfig";
import {
  collection, deleteField, doc, getDocs, serverTimestamp, setDoc,
} from "firebase/firestore";
import { httpsCallable } from "firebase/functions";
import Snackbar from "@mui/material/Snackbar";
import Alert from "@mui/material/Alert";
import "../styles/Users.css";
import StateCard from "../components/StateCard";
import ConfirmDialog from "../components/ConfirmDialog";
import { useAdminAuth } from "../context/AdminAuthContext";
import { useProject } from "../context/ProjectContext";
import { DEFAULT_PROJECT_ID, filterByProject } from "../utils/projects";
import { buildCsv, downloadCsv } from "../utils/exportCsv";

// Szerepkör olvasható neve. A 'developer' a platform-szintű (admin fölötti)
// szerep, ezért külön jelenik meg, nem "Felhasználó"-ként.
const roleLabel = (role) => {
  if (role === "developer") return "Developer";
  if (role === "admin") return "Admin";
  return "Felhasználó";
};

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
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [snack, setSnack] = useState({ open: false, message: "", severity: "success" });
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const PAGE_SIZE = 50;
  // Developer-only műveletek: szerep-adás és teljes törlés.
  const { userRole, userEmail } = useAdminAuth();
  const isDeveloper = userRole === "developer";
  const { projects, activeProjectId } = useProject();
  const [roleFilter, setRoleFilter] = useState("all");
  const [actionBusyId, setActionBusyId] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [inviteForm, setInviteForm] = useState({ email: "", name: "", projectId: "" });
  const [inviteBusy, setInviteBusy] = useState(false);
  const [inviteLink, setInviteLink] = useState("");
  // Jutalom-beváltás nyomon követése: melyik jutalmakhoz tartozik fizikai/
  // kedvezmény jutalom (rewardInfo), és felhasználónként (lusta betöltéssel,
  // csak kinyitáskor) melyiket váltották már be.
  const [achievementDefs, setAchievementDefs] = useState([]);
  const [expandedRewardsId, setExpandedRewardsId] = useState(null);
  const [userRewards, setUserRewards] = useState({});
  const [rewardsLoadingId, setRewardsLoadingId] = useState(null);
  async function fetchUsers() {
    try {
      setLoading(true);
      setError(null);

      const [usersSnapshot, progressSnapshot, stationsSnapshot, leaderboardSnapshot] =
        await Promise.all([
          getDocs(collection(db, "users")),
          getDocs(collection(db, "user_progress")),
          getDocs(collection(db, "stations")),
          // A rangsor UGYANABBÓL a forrásból jön, mint a mobilappban: a
          // településenkénti ranglistából. Enélkül más sorrend jelenne meg a
          // weben (globális pont) és a telefonon (települési pont).
          getDocs(collection(db, "leaderboards", activeProjectId, "entries")),
        ]);

      const projectPoints = new Map();
      leaderboardSnapshot.docs.forEach((d) => {
        projectPoints.set(d.id, Number(d.data()?.points) || 0);
      });

      // Az összes állomás száma globális (a user_progress nem tárolja),
      // ebből számoljuk a valós haladást minden felhasználónál.
      const totalStationsCount = stationsSnapshot.size;

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

          const totalStations = totalStationsCount;
          const progress =
            totalStations > 0
              ? Math.min(100, Math.round((completedStations / totalStations) * 100))
              : 0;

          return {
            id: progressDoc.id,
            userId: progressData.userId || progressDoc.id,
            uid: progressData.userId || progressDoc.id,
            email: progressData.email || "",
            userName: progressData.name || progressData.userName || "Ismeretlen",
            role: "user",
            tripId: progressData.tripId || "N/A",
            completedStations,
            totalStations,
            progress,
            points: projectPoints.get(progressDoc.id) ?? 0,
            lastUpdated:
              progressData.updatedAt || progressData.lastUpdated || null,
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
          projectId: userData.projectId || "",
          banned: userData.banned === true,
          tripId: "N/A",
          completedStations: 0,
          totalStations: totalStationsCount,
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
    // Projektváltáskor újratöltünk (más település ranglistája/tartalma).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeProjectId]);

  // A jutalom-definíciók (rewardInfo) külön, könnyű lekérdezéssel – csak
  // ezekre kell a per-felhasználó beváltás-állapot, a fő fetchUsers()-t
  // ezért nem terheljük vele.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const snap = await getDocs(collection(db, "achievements"));
        const all = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
        if (!cancelled) setAchievementDefs(filterByProject(all, activeProjectId));
      } catch {
        if (!cancelled) setAchievementDefs([]);
      }
    })();
    return () => { cancelled = true; };
  }, [activeProjectId]);

  // Csak azok a jutalom-definíciók érdekesek itt, amelyekhez tényleg jár
  // fizikai/kedvezmény jutalom (rewardInfo kitöltve).
  const rewardAchievements = useMemo(
    () => achievementDefs.filter((a) => (a.rewardInfo || "").trim()),
    [achievementDefs],
  );
  const hasAnyRewards = rewardAchievements.length > 0;

  // Egy felhasználó jutalom-panelének kinyitása/becsukása. Első kinyitáskor
  // lekéri a feloldott achievementjeit, és összeveti a jutalommal járókkal.
  const handleToggleRewardsPanel = async (user) => {
    const uid = user.uid || user.id;
    if (!uid) return;
    if (expandedRewardsId === uid) {
      setExpandedRewardsId(null);
      return;
    }
    setExpandedRewardsId(uid);
    if (userRewards[uid]) return; // már betöltve

    setRewardsLoadingId(uid);
    try {
      const snap = await getDocs(
        collection(db, "user_progress", uid, "unlocked_achievements")
      );
      const rewardIds = new Set(rewardAchievements.map((a) => a.id));
      const rows = snap.docs
        .filter((d) => rewardIds.has(d.id))
        .map((d) => ({ id: d.id, ...d.data() }));
      setUserRewards((prev) => ({ ...prev, [uid]: rows }));
    } catch {
      setSnack({ open: true, severity: "error", message: "Nem sikerült betölteni a jutalmakat." });
    } finally {
      setRewardsLoadingId(null);
    }
  };

  // Beváltottnak / vissza nem váltottnak jelölés – admin (saját település) és
  // developer is megteheti, ugyanúgy, ahogy a jutalmak (Achievements oldal)
  // szerkesztését is. A cél: egy fizikai/kedvezmény jutalmat ne lehessen
  // többször felmutatni.
  const handleToggleRedeemed = async (uid, achievementId, currentlyRedeemed) => {
    try {
      await setDoc(
        doc(db, "user_progress", uid, "unlocked_achievements", achievementId),
        currentlyRedeemed
          ? { redeemedAt: deleteField(), redeemedBy: deleteField() }
          : { redeemedAt: serverTimestamp(), redeemedBy: userEmail || null },
        { merge: true }
      );
      setUserRewards((prev) => ({
        ...prev,
        [uid]: (prev[uid] || []).map((r) =>
          r.id === achievementId
            ? {
                ...r,
                redeemedAt: currentlyRedeemed ? null : new Date(),
                redeemedBy: currentlyRedeemed ? null : userEmail || null,
              }
            : r
        ),
      }));
      setSnack({
        open: true,
        severity: "success",
        message: currentlyRedeemed ? "Beváltás visszavonva." : "Jutalom beváltottnak jelölve.",
      });
    } catch (err) {
      setSnack({
        open: true,
        severity: "error",
        message: `Nem sikerült a jelölés: ${err.message || err}`,
      });
    }
  };

  const handleExportCsv = () => {
    const columns = [
      { key: "rank", label: "Rang" },
      { key: "userName", label: "Név" },
      { key: "email", label: "Email" },
      { key: "role", label: "Szerepkör", format: (v) => roleLabel(v) },
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

  // A users doksi azonosítója: ahonnan olvastuk (id), egyébként az uid.
  const targetDocId = (user) => user.id || user.uid;

  // Admin jog adása/elvétele. A szabályok szerint szerepet csak developer
  // állíthat, ezért a gomb is csak neki jelenik meg.
  const handleToggleAdmin = async (user) => {
    const id = targetDocId(user);
    if (!id) return;
    const nextRole = user.role === "admin" ? "user" : "admin";
    setActionBusyId(id);
    try {
      await setDoc(
        doc(db, "users", id),
        {
          role: nextRole,
          ...(user.uid ? { uid: user.uid } : {}),
          ...(user.email ? { email: user.email } : {}),
        },
        { merge: true },
      );
      setSnack({
        open: true,
        severity: "success",
        message:
          nextRole === "admin"
            ? `${user.userName} mostantól admin.`
            : `${user.userName} admin joga visszavonva.`,
      });
      await fetchUsers();
    } catch (err) {
      setSnack({
        open: true,
        severity: "error",
        message: `Nem sikerült a szerep módosítása: ${err.message || err}`,
      });
    } finally {
      setActionBusyId(null);
    }
  };

  // Település hozzárendelése egy adminhoz: ettől kezdve ő csak annak a
  // településnek a tartalmát látja/kezeli (users/{uid}.projectId).
  const handleAssignProject = async (user, projectId) => {
    const id = targetDocId(user);
    if (!id) return;
    setActionBusyId(id);
    try {
      await setDoc(doc(db, "users", id), { projectId }, { merge: true });
      setSnack({
        open: true,
        severity: "success",
        message: `${user.userName} települése: ${
          projects.find((p) => p.id === projectId)?.name || projectId
        }`,
      });
      await fetchUsers();
    } catch (err) {
      setSnack({
        open: true,
        severity: "error",
        message: `Nem sikerült a hozzárendelés: ${err.message || err}`,
      });
    } finally {
      setActionBusyId(null);
    }
  };

  // Admin meghívása e-mail alapján. A szerver létrehozza/frissíti a fiókot
  // admin szerepkörrel, és visszaad egy jelszó-beállító linket, amit a
  // meghívottnak kell eljuttatni (nem kell külön e-mail-küldő szolgáltatás).
  const handleInvite = async () => {
    const email = inviteForm.email.trim();
    if (!email) return;
    setInviteBusy(true);
    setInviteLink("");
    try {
      const call = httpsCallable(functions, "inviteAdmin");
      const res = await call({
        email,
        name: inviteForm.name.trim(),
        projectId: inviteForm.projectId || projects[0]?.id,
      });
      setInviteLink(res.data?.resetLink || "");
      setSnack({
        open: true,
        severity: "success",
        message: res.data?.created
          ? `${email} meghívva adminként.`
          : `${email} admin jogot kapott.`,
      });
      await fetchUsers();
    } catch (err) {
      const reason = err?.details?.reason || err?.message || err;
      setSnack({ open: true, severity: "error", message: `Meghívás sikertelen: ${reason}` });
    } finally {
      setInviteBusy(false);
    }
  };

  // Kitiltás / feloldás: visszafordítható alternatíva a végleges törlés helyett.
  const handleToggleBan = async (user) => {
    const uid = user.uid || user.id;
    if (!uid) return;
    setActionBusyId(user.id || user.uid);
    try {
      const call = httpsCallable(functions, "setUserBanned");
      await call({ uid, banned: !user.banned });
      setSnack({
        open: true,
        severity: "success",
        message: user.banned
          ? `${user.userName} kitiltása feloldva.`
          : `${user.userName} kitiltva (nem tud belépni).`,
      });
      await fetchUsers();
    } catch (err) {
      const reason = err?.details?.reason || err?.message || err;
      setSnack({ open: true, severity: "error", message: `Sikertelen: ${reason}` });
    } finally {
      setActionBusyId(null);
    }
  };

  // Teljes törlés: Auth-fiók + minden kapcsolódó dokumentum, szerveroldalon
  // (adminDeleteUser callable, developer-jogosultsággal).
  const handleDeleteUser = async () => {
    const user = deleteTarget;
    if (!user) return;
    const uid = user.uid || user.id;
    setDeleteTarget(null);
    setActionBusyId(uid);
    try {
      const call = httpsCallable(functions, "adminDeleteUser");
      await call({ uid });
      setSnack({
        open: true,
        severity: "success",
        message: `${user.userName} törölve.`,
      });
      await fetchUsers();
    } catch (err) {
      const reason = err?.details?.reason || err?.message || err;
      setSnack({ open: true, severity: "error", message: `Törlés sikertelen: ${reason}` });
    } finally {
      setActionBusyId(null);
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
  // Megjegyzés: a fenti számláló a teljes körre vonatkozik; a lista a
  // szerep-hierarchia szerint szűrt (lásd visibleUsers).
  // reduce (not Math.max(...spread)) so this stays safe with thousands of users.
  const maxPoints = users.reduce((max, u) => (u.points > max ? u.points : max), 0);

  // Search + pagination keep the ranking responsive even with thousands of users:
  // only one page worth of rows is ever rendered into the DOM.
  const q = search.trim().toLowerCase();
  // Szerep-hierarchia: mindenki legfeljebb a SAJÁT szintjét látja. Az admin
  // nem látja a developereket (a developer mindenkit lát).
  const visibleUsers = isDeveloper
    ? users
    : users.filter((u) => (u.role || "user") !== "developer");

  const bySearch = q
    ? visibleUsers.filter(
        (u) =>
          (u.userName && u.userName.toLowerCase().includes(q)) ||
          (u.email && u.email.toLowerCase().includes(q))
      )
    : visibleUsers;
  // Szerep szerinti szűrő (pl. csak az adminok listázása).
  // A 'developer' szűrő nem-developernél nem érvényesül (nem is választható).
  const effectiveRoleFilter =
    roleFilter === "developer" && !isDeveloper ? "all" : roleFilter;
  const filteredUsers =
    effectiveRoleFilter === "all"
      ? bySearch
      : bySearch.filter((u) => (u.role || "user") === effectiveRoleFilter);
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
            <select
              className="users-role-filter"
              value={roleFilter}
              onChange={(e) => {
                setRoleFilter(e.target.value);
                setPage(1);
              }}
              title="Szűrés szerepkör szerint"
            >
              <option value="all">Minden szerep</option>
              {/* A 'developer' szűrő csak developernek – az admin a
                  developereket nem is látja, így nem is szűrhet rájuk. */}
              {isDeveloper && <option value="developer">Developer</option>}
              <option value="admin">Admin</option>
              <option value="user">Felhasználó</option>
            </select>
            {isDeveloper && (
              <button
                type="button"
                className="users-invite-btn"
                onClick={() => {
                  setInviteForm({ email: "", name: "", projectId: projects[0]?.id || "" });
                  setInviteLink("");
                  setInviteOpen(true);
                }}
              >
                ＋ Admin meghívása
              </button>
            )}
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
                <div className={`users-header${isDeveloper ? " with-actions" : ""}`}>
                  <div className="rank-col">Rang</div>
                  <div className="name-col">Felhasználó</div>
                  <div className="role-col">Szerepkör</div>
                  <div className="points-col">Pontok</div>
                  <div className="progress-col">Haladás</div>
                  <div className="activity-col">Utolsó aktivitás</div>
                  {isDeveloper && <div className="actions-col">Műveletek</div>}
                </div>

                {pagedUsers.map((user, localIndex) => {
                  const index = pageStart + localIndex;
                  const uid = user.uid || user.id;
                  const rewardsExpanded = hasAnyRewards && expandedRewardsId === uid;
                  return (
                    <React.Fragment key={user.id || user.userId}>
                    <div
                      className={`user-row${index < 3 ? " top" : ""}${isDeveloper ? " with-actions" : ""}`}
                    >
                      <div className="rank-col">
                        <div className="rank-badge">{getRankBadge(index)}</div>
                      </div>

                      <div className="name-col">
                        <strong title={user.uid ? `uid: ${user.uid}` : undefined}>
                          {user.userName}
                          {user.banned && <span className="banned-pill">kitiltva</span>}
                        </strong>
                        <small>{user.email || "Nincs email"}</small>
                        {hasAnyRewards && (
                          <button
                            type="button"
                            className="user-rewards-toggle"
                            onClick={() => handleToggleRewardsPanel(user)}
                            title="Feloldott jutalmak és beváltás-állapot"
                          >
                            🎁 Jutalmak {rewardsExpanded ? "▲" : "▼"}
                          </button>
                        )}
                      </div>

                      <div className="role-col">
                        <span className={`role-badge ${user.role === "admin" || user.role === "developer" ? "admin" : "user"}`}>
                          {roleLabel(user.role)}
                        </span>
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

                      {isDeveloper && (() => {
                        // Saját magadon és más developeren nem lehet műveletet
                        // végezni (kizárás / véletlen jogvesztés elkerülése).
                        const isSelf =
                          !!userEmail && !!user.email && user.email === userEmail;
                        const isOtherDeveloper = user.role === "developer";
                        const locked = isSelf || isOtherDeveloper;
                        const busy = actionBusyId === (user.id || user.uid);
                        return (
                          <div className="actions-col">
                            {locked ? (
                              <span className="actions-locked">
                                {isSelf ? "saját fiók" : "developer"}
                              </span>
                            ) : (
                              <>
                                <button
                                  type="button"
                                  className="user-action-btn"
                                  disabled={busy}
                                  onClick={() => handleToggleAdmin(user)}
                                  title={
                                    user.role === "admin"
                                      ? "Admin jog visszavonása"
                                      : "Admin jog adása"
                                  }
                                >
                                  {user.role === "admin" ? "Jog elvétele" : "Admin jog"}
                                </button>
                                <button
                                  type="button"
                                  className="user-action-btn"
                                  disabled={busy}
                                  onClick={() => handleToggleBan(user)}
                                  title={
                                    user.banned
                                      ? "Kitiltás feloldása"
                                      : "Kitiltás (nem tud belépni, visszafordítható)"
                                  }
                                >
                                  {user.banned ? "Feloldás" : "Kitiltás"}
                                </button>
                                <button
                                  type="button"
                                  className="user-action-btn danger"
                                  disabled={busy}
                                  onClick={() => setDeleteTarget(user)}
                                  title="Felhasználó és minden adatának végleges törlése"
                                >
                                  Törlés
                                </button>
                                {user.role === "admin" && (
                                  <select
                                    className="user-project-select"
                                    disabled={busy}
                                    value={user.projectId || DEFAULT_PROJECT_ID}
                                    onChange={(e) =>
                                      handleAssignProject(user, e.target.value)
                                    }
                                    title="Melyik települést kezelheti"
                                  >
                                    {projects.map((p) => (
                                      <option key={p.id} value={p.id}>
                                        {p.name || p.id}
                                      </option>
                                    ))}
                                  </select>
                                )}
                              </>
                            )}
                          </div>
                        );
                      })()}
                    </div>

                    {rewardsExpanded && (
                      <div className="user-rewards-panel">
                        {rewardsLoadingId === uid ? (
                          <p className="user-rewards-empty">Betöltés...</p>
                        ) : (userRewards[uid] || []).length === 0 ? (
                          <p className="user-rewards-empty">
                            Nincs jutalommal járó feloldott achievementje.
                          </p>
                        ) : (
                          <ul className="user-rewards-list">
                            {userRewards[uid].map((r) => {
                              const def = rewardAchievements.find((a) => a.id === r.id);
                              const redeemed = !!r.redeemedAt;
                              return (
                                <li key={r.id} className="user-rewards-item">
                                  <span className="user-rewards-icon">{def?.icon || "🎁"}</span>
                                  <div className="user-rewards-info">
                                    <strong>{def?.name || r.id}</strong>
                                    <span className="user-rewards-desc">{def?.rewardInfo}</span>
                                  </div>
                                  <button
                                    type="button"
                                    className={`user-rewards-btn${redeemed ? " redeemed" : ""}`}
                                    onClick={() => handleToggleRedeemed(uid, r.id, redeemed)}
                                  >
                                    {redeemed
                                      ? `✅ Beváltva ${formatDate(r.redeemedAt)}`
                                      : "Beváltottnak jelölés"}
                                  </button>
                                </li>
                              );
                            })}
                          </ul>
                        )}
                      </div>
                    )}
                    </React.Fragment>
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

      {inviteOpen && (
        <div
          className="invite-backdrop"
          role="presentation"
          onClick={(e) => e.target === e.currentTarget && setInviteOpen(false)}
        >
          <div className="invite-modal" role="dialog" aria-modal="true">
            <h2>Admin meghívása</h2>
            <p className="invite-hint">
              A megadott e-mail címhez admin fiók jön létre (ha még nincs), és
              hozzárendeljük a kiválasztott településhez. A mentés után kapsz egy
              jelszó-beállító linket, amit el kell juttatnod a meghívottnak.
            </p>

            <label className="invite-label" htmlFor="invite-email">E-mail *</label>
            <input
              id="invite-email"
              className="invite-input"
              type="email"
              value={inviteForm.email}
              disabled={inviteBusy}
              onChange={(e) => setInviteForm((f) => ({ ...f, email: e.target.value }))}
              placeholder="pl. admin@mencshely.hu"
            />

            <label className="invite-label" htmlFor="invite-name">Név</label>
            <input
              id="invite-name"
              className="invite-input"
              type="text"
              value={inviteForm.name}
              disabled={inviteBusy}
              onChange={(e) => setInviteForm((f) => ({ ...f, name: e.target.value }))}
              placeholder="pl. Kiss János"
            />

            <label className="invite-label" htmlFor="invite-project">Település</label>
            <select
              id="invite-project"
              className="invite-input"
              value={inviteForm.projectId}
              disabled={inviteBusy}
              onChange={(e) => setInviteForm((f) => ({ ...f, projectId: e.target.value }))}
            >
              {projects.map((p) => (
                <option key={p.id} value={p.id}>{p.name || p.id}</option>
              ))}
            </select>

            {inviteLink && (
              <div className="invite-link-box">
                <strong>Jelszó-beállító link (küldd el a meghívottnak):</strong>
                <textarea readOnly rows="3" value={inviteLink} onFocus={(e) => e.target.select()} />
              </div>
            )}

            <div className="invite-actions">
              <button
                type="button"
                className="btn-primary"
                disabled={inviteBusy || !inviteForm.email.trim()}
                onClick={handleInvite}
              >
                {inviteBusy ? "Meghívás..." : "Meghívás"}
              </button>
              <button
                type="button"
                className="btn-secondary"
                onClick={() => setInviteOpen(false)}
              >
                {inviteLink ? "Bezárás" : "Mégse"}
              </button>
            </div>
          </div>
        </div>
      )}

      <ConfirmDialog
        open={deleteTarget !== null}
        title="Felhasználó törlése"
        message={
          deleteTarget
            ? `Biztosan törlöd: ${deleteTarget.userName}${deleteTarget.email ? ` (${deleteTarget.email})` : ""}? ` +
              "A fiók és MINDEN adata (haladás, jutalmak, ranglista) véglegesen törlődik. Ez nem vonható vissza."
            : ""
        }
        confirmText="Végleges törlés"
        onConfirm={handleDeleteUser}
        onClose={() => setDeleteTarget(null)}
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


