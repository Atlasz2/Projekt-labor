import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import Users from "./Users";

// ── Mocks ──────────────────────────────────────────────────────────────────
vi.mock("../firebaseConfig", () => ({ db: {} }));
vi.mock("../styles/Users.css", () => ({}));
vi.mock("../context/ProjectContext", () => ({
  useProject: () => ({
    activeProjectId: "nagyvazsony",
    activeProject: { id: "nagyvazsony", name: "Nagyvázsony" },
    canSwitchProject: false,
    projects: [{ id: "nagyvazsony", name: "Nagyvázsony" }],
  }),
}));

vi.mock("../context/AdminAuthContext", () => ({
  useAdminAuth: () => ({ userEmail: "admin@test.hu" }),
}));

vi.mock("firebase/firestore", () => ({
  // A valós hívások néha több útvonal-szegmenst adnak át (pl. a leaderboard
  // vagy egy felhasználó unlocked_achievements alkollekciója) – ezeket "/"-szel
  // összefűzve adjuk vissza, hogy a teszt meg tudja különböztetni őket.
  collection: vi.fn((_db, ...parts) => parts.join("/")),
  getDocs: vi.fn(),
  doc: vi.fn((_db, ...parts) => ({ _path: parts.join("/") })),
  setDoc: vi.fn().mockResolvedValue(undefined),
  serverTimestamp: vi.fn(() => "SERVER_TS"),
  deleteField: vi.fn(() => "DELETE_FIELD"),
}));

import { deleteField, getDocs, serverTimestamp, setDoc } from "firebase/firestore";

const snap = (rows) => ({
  docs: rows.map((r) => ({ id: r.id, data: () => r.data })),
  size: rows.length,
});

// Route getDocs by collection name so users and user_progress get distinct data.
// A rangsor a településenkénti ranglistából jön (mint a mobilappban), ezért a
// haladás totalPoints értékéből építünk hozzá ranglista-bejegyzéseket.
const setData = (users, progress = [], achievements = [], unlockedByUid = {}) =>
  getDocs.mockImplementation((col) => {
    if (col === "user_progress") return Promise.resolve(snap(progress));
    if (typeof col === "string" && col.startsWith("leaderboards/")) {
      return Promise.resolve(
        snap(
          progress.map((row) => ({
            id: row.id,
            data: { points: row.data.totalPoints ?? 0 },
          })),
        ),
      );
    }
    if (col === "achievements") return Promise.resolve(snap(achievements));
    if (typeof col === "string" && col.endsWith("/unlocked_achievements")) {
      const uid = col.split("/")[1];
      return Promise.resolve(snap(unlockedByUid[uid] || []));
    }
    return Promise.resolve(snap(users));
  });

const userDoc = (id, overrides = {}) => ({
  id,
  data: { uid: id, email: `${id}@test.hu`, name: id, role: "user", ...overrides },
});

const progressDoc = (id, overrides = {}) => ({
  id,
  data: { userId: id, email: `${id}@test.hu`, userName: id, totalPoints: 0, ...overrides },
});

const achievementDoc = (id, overrides = {}) => ({
  id,
  data: { name: id, icon: "🏆", rewardInfo: "", ...overrides },
});

const unlockedDoc = (id, overrides = {}) => ({
  id,
  data: { unlockedAt: "2026-01-01", ...overrides },
});

const renderUsers = () => render(<Users />);

describe("Users", () => {
  beforeEach(() => { vi.clearAllMocks(); });

  it("merges users + user_progress and shows names with points", async () => {
    setData(
      [userDoc("anna", { uid: "anna", name: "Anna" })],
      [progressDoc("anna", { userId: "anna", userName: "Anna", totalPoints: 50 })]
    );
    renderUsers();
    await waitFor(() => expect(screen.getByText("Anna")).toBeInTheDocument());
    expect(screen.getByText("50 pont")).toBeInTheDocument();
  });

  it("shows the role badge but offers no way to change roles from the UI", async () => {
    setData([
      userDoc("anna", { uid: "anna", name: "Anna", role: "user" }),
      userDoc("admin", { uid: "admin", email: "admin@test.hu", name: "AdminUser", role: "admin" }),
    ]);
    renderUsers();
    await waitFor(() => expect(screen.getByText("Anna")).toBeInTheDocument());

    // The role is shown for information (as badges)...
    expect(document.querySelector(".role-badge.user")).toBeInTheDocument();
    expect(document.querySelector(".role-badge.admin")).toBeInTheDocument();

    // ...but the promote/demote control is gone (roles are set in Firestore only).
    expect(
      screen.queryByRole("button", { name: /Adminná tesz|Admin jog/ })
    ).not.toBeInTheDocument();
  });

  it("renders the ranking sorted by points (highest first)", async () => {
    setData(
      [
        userDoc("anna", { uid: "anna", name: "Anna" }),
        userDoc("bela", { uid: "bela", name: "Bela" }),
      ],
      [
        progressDoc("anna", { userId: "anna", userName: "Anna", totalPoints: 30 }),
        progressDoc("bela", { userId: "bela", userName: "Bela", totalPoints: 90 }),
      ]
    );
    renderUsers();
    await waitFor(() => expect(screen.getByText("Anna")).toBeInTheDocument());

    const rows = document.querySelectorAll(".user-row");
    expect(within(rows[0]).getByText("Bela")).toBeInTheDocument();
    expect(within(rows[1]).getByText("Anna")).toBeInTheDocument();
  });

  it("paginates the ranking to 50 rows per page", async () => {
    const progress = Array.from({ length: 60 }, (_, i) =>
      progressDoc(`u${i}`, { userId: `u${i}`, userName: `User ${i}`, totalPoints: 1000 - i })
    );
    setData([], progress);
    renderUsers();
    await waitFor(() => expect(screen.getByText("User 0")).toBeInTheDocument());

    expect(document.querySelectorAll(".user-row")).toHaveLength(50);
    expect(screen.getByText(/1 \/ 2 oldal/)).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Következő →" }));
    expect(document.querySelectorAll(".user-row")).toHaveLength(10);
  });

  it("filters the ranking with the search box", async () => {
    setData([], [
      progressDoc("anna", { userId: "anna", userName: "Anna", totalPoints: 10 }),
      progressDoc("bela", { userId: "bela", userName: "Bela", totalPoints: 20 }),
    ]);
    renderUsers();
    await waitFor(() => expect(screen.getByText("Anna")).toBeInTheDocument());

    await userEvent.type(screen.getByPlaceholderText(/Keresés/), "anna");
    expect(screen.getByText("Anna")).toBeInTheDocument();
    expect(screen.queryByText("Bela")).not.toBeInTheDocument();
  });

  it("shows a no-result state when the search matches nothing", async () => {
    setData([], [progressDoc("anna", { userId: "anna", userName: "Anna", totalPoints: 10 })]);
    renderUsers();
    await waitFor(() => expect(screen.getByText("Anna")).toBeInTheDocument());

    await userEvent.type(screen.getByPlaceholderText(/Keresés/), "zzzzz");
    await waitFor(() => expect(screen.getByText("Nincs találat")).toBeInTheDocument());
  });

  describe("jutalom-beváltás", () => {
    const rewardAchievement = achievementDoc("explorer", {
      name: "Felfedező",
      icon: "🧭",
      rewardInfo: "10% kedvezmény a cukrászdában",
    });

    it("nem jelenik meg a Jutalmak jelölő, ha a településnek nincs jutalommal járó achievementje", async () => {
      setData(
        [],
        [progressDoc("anna", { userId: "anna", userName: "Anna", totalPoints: 10 })],
        [achievementDoc("no_reward", { name: "Sima", rewardInfo: "" })],
      );
      renderUsers();
      await waitFor(() => expect(screen.getByText("Anna")).toBeInTheDocument());
      expect(screen.queryByText(/🎁 Jutalmak/)).not.toBeInTheDocument();
    });

    it("kinyitva megmutatja a felhasználó feloldott, jutalommal járó achievementjeit", async () => {
      setData(
        [],
        [progressDoc("anna", { userId: "anna", userName: "Anna", totalPoints: 10 })],
        [rewardAchievement],
        { anna: [unlockedDoc("explorer")] },
      );
      renderUsers();
      await waitFor(() => expect(screen.getByText("Anna")).toBeInTheDocument());

      await waitFor(() => expect(screen.getByText(/🎁 Jutalmak/)).toBeInTheDocument());
      await userEvent.click(screen.getByText(/🎁 Jutalmak/));
      await waitFor(() =>
        expect(screen.getByText("10% kedvezmény a cukrászdában")).toBeInTheDocument(),
      );
      expect(screen.getByText("Beváltottnak jelölés")).toBeInTheDocument();
    });

    it("beváltottnak jelölésre a redeemedAt/redeemedBy mezőt írja, majd visszavonható", async () => {
      setData(
        [],
        [progressDoc("anna", { userId: "anna", userName: "Anna", totalPoints: 10 })],
        [rewardAchievement],
        { anna: [unlockedDoc("explorer")] },
      );
      renderUsers();
      await waitFor(() => expect(screen.getByText("Anna")).toBeInTheDocument());
      await waitFor(() => expect(screen.getByText(/🎁 Jutalmak/)).toBeInTheDocument());
      await userEvent.click(screen.getByText(/🎁 Jutalmak/));
      await waitFor(() => expect(screen.getByText("Beváltottnak jelölés")).toBeInTheDocument());

      await userEvent.click(screen.getByText("Beváltottnak jelölés"));
      await waitFor(() =>
        expect(setDoc).toHaveBeenCalledWith(
          expect.objectContaining({ _path: "user_progress/anna/unlocked_achievements/explorer" }),
          { redeemedAt: serverTimestamp(), redeemedBy: "admin@test.hu" },
          { merge: true },
        ),
      );
      await waitFor(() => expect(screen.getByText(/✅ Beváltva/)).toBeInTheDocument());

      await userEvent.click(screen.getByText(/✅ Beváltva/));
      await waitFor(() =>
        expect(setDoc).toHaveBeenLastCalledWith(
          expect.objectContaining({ _path: "user_progress/anna/unlocked_achievements/explorer" }),
          { redeemedAt: deleteField(), redeemedBy: deleteField() },
          { merge: true },
        ),
      );
      await waitFor(() => expect(screen.getByText("Beváltottnak jelölés")).toBeInTheDocument());
    });
  });
});
