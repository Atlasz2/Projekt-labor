import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import Users from "./Users";

// ── Mocks ──────────────────────────────────────────────────────────────────
vi.mock("../firebaseConfig", () => ({ db: {} }));
vi.mock("../styles/Users.css", () => ({}));
vi.mock("../context/AdminAuthContext", () => ({
  useAdminAuth: () => ({ userEmail: "admin@test.hu" }),
}));

vi.mock("firebase/firestore", () => ({
  collection: vi.fn((_db, name) => name),
  getDocs: vi.fn(),
  doc: vi.fn((_db, col, id) => ({ col, id })),
  updateDoc: vi.fn().mockResolvedValue(undefined),
}));

import { getDocs, updateDoc } from "firebase/firestore";

const snap = (rows) => ({
  docs: rows.map((r) => ({ id: r.id, data: () => r.data })),
  size: rows.length,
});

// Route getDocs by collection name so users and user_progress get distinct data.
const setData = (users, progress = []) =>
  getDocs.mockImplementation((col) =>
    Promise.resolve(col === "user_progress" ? snap(progress) : snap(users))
  );

const userDoc = (id, overrides = {}) => ({
  id,
  data: { uid: id, email: `${id}@test.hu`, name: id, role: "user", ...overrides },
});

const progressDoc = (id, overrides = {}) => ({
  id,
  data: { userId: id, email: `${id}@test.hu`, userName: id, totalPoints: 0, ...overrides },
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

  it("shows a role toggle for real accounts but not for progress-only users", async () => {
    setData(
      [userDoc("anna", { uid: "anna", name: "Anna" })],
      [progressDoc("bela", { userId: "bela", userName: "Bela", totalPoints: 80 })]
    );
    renderUsers();
    await waitFor(() => expect(screen.getByText("Bela")).toBeInTheDocument());

    // Anna has a users doc → exactly one toggle button; Bela (progress-only) has none.
    const toggles = screen.getAllByRole("button", { name: /Adminná tesz|Admin jog elvétele/ });
    expect(toggles).toHaveLength(1);
    expect(toggles[0]).toHaveTextContent("Adminná tesz");
  });

  it("disables the toggle on the currently logged-in admin's own row", async () => {
    setData([
      userDoc("admin", { uid: "admin", email: "admin@test.hu", name: "AdminUser", role: "admin" }),
    ]);
    renderUsers();
    await waitFor(() => expect(screen.getByText("AdminUser")).toBeInTheDocument());
    expect(screen.getByRole("button", { name: "Admin jog elvétele" })).toBeDisabled();
  });

  it("promotes a user to admin after confirmation", async () => {
    setData([userDoc("anna", { uid: "anna", name: "Anna", role: "user" })]);
    renderUsers();
    await waitFor(() => expect(screen.getByText("Anna")).toBeInTheDocument());

    await userEvent.click(screen.getByRole("button", { name: "Adminná tesz" }));

    // Confirmation dialog opens with the promote action
    const confirmBtn = await screen.findByRole("button", { name: "Admin jog adása" });
    await userEvent.click(confirmBtn);

    await waitFor(() => expect(updateDoc).toHaveBeenCalledTimes(1));
    expect(updateDoc.mock.calls[0][0]).toEqual({ col: "users", id: "anna" });
    expect(updateDoc.mock.calls[0][1]).toEqual({ role: "admin" });
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
});
