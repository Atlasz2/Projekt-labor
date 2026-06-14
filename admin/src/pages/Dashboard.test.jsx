import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { MemoryRouter } from "react-router-dom";
import Dashboard from "./Dashboard";

vi.mock("../firebaseConfig", () => ({ db: {} }));
vi.mock("../styles/Dashboard.css", () => ({}));

vi.mock("firebase/firestore", () => ({
  collection: vi.fn(),
  getDocs: vi.fn(),
  query: vi.fn(),
  where: vi.fn(),
  doc: vi.fn(),
  setDoc: vi.fn().mockResolvedValue(undefined),
  orderBy: vi.fn(),
  limit: vi.fn(),
}));

import { getDocs } from "firebase/firestore";

const makeSnap = (size = 0, docs = []) => ({ docs, size });
const makeProgressSnap = (points = []) => ({
  docs: points.map((p) => ({ data: () => ({ totalPoints: p }) })),
  size: points.length,
});

const mockSuccess = () => {
  getDocs
    .mockResolvedValueOnce(makeSnap(3))    // trips
    .mockResolvedValueOnce(makeSnap(1))    // activeTrips
    .mockResolvedValueOnce(makeSnap(5))    // stations
    .mockResolvedValueOnce(makeSnap(2))    // users
    .mockResolvedValueOnce(makeProgressSnap([100, 200]))  // user_progress
    .mockResolvedValueOnce({ docs: [], size: 0 })          // achievements
    .mockResolvedValueOnce({ docs: [], size: 0 });         // stats_daily trend read
};

const renderDashboard = () => render(<MemoryRouter><Dashboard /></MemoryRouter>);

describe("Dashboard", () => {
  beforeEach(() => { vi.clearAllMocks(); });

  it("shows loading StateCard initially", () => {
    getDocs.mockResolvedValue(makeSnap());
    renderDashboard();
    expect(screen.getByText("Dashboard betöltése...")).toBeInTheDocument();
  });

  it("shows stats grid after successful load", async () => {
    mockSuccess();
    renderDashboard();
    await waitFor(() => expect(screen.getByText("Statisztikák")).toBeInTheDocument());
  });

  it("shows correct stat values after load", async () => {
    mockSuccess();
    renderDashboard();
    await waitFor(() => expect(screen.getByText("Összes túra")).toBeInTheDocument());
    expect(screen.getByText("Aktív túrák")).toBeInTheDocument();
    expect(screen.getByText("Követett haladás")).toBeInTheDocument();
    expect(screen.getByText("Jutalmak")).toBeInTheDocument();
  });

  it("shows error StateCard when fetch fails", async () => {
    getDocs.mockRejectedValue(new Error("hálózati hiba"));
    renderDashboard();
    await waitFor(() =>
      expect(screen.getByText("Nem sikerült betölteni a Dashboardot")).toBeInTheDocument()
    );
  });

  it("shows Újrapróbálás button in error state", async () => {
    getDocs.mockRejectedValue(new Error("fail"));
    renderDashboard();
    await waitFor(() => expect(screen.getByText("Újrapróbálás")).toBeInTheDocument());
  });

  it("Újrapróbálás triggers refetch and shows stats", async () => {
    getDocs.mockRejectedValue(new Error("fail"));
    renderDashboard();
    await waitFor(() => expect(screen.getByText("Újrapróbálás")).toBeInTheDocument());
    getDocs.mockReset();
    mockSuccess();
    await userEvent.click(screen.getByText("Újrapróbálás"));
    await waitFor(() => expect(screen.getByText("Statisztikák")).toBeInTheDocument());
  });

  it("shows quick actions after load", async () => {
    mockSuccess();
    renderDashboard();
    await waitFor(() => expect(screen.getByText("Gyors műveletek")).toBeInTheDocument());
  });

  it("refresh button is disabled while loading", () => {
    getDocs.mockResolvedValue(makeSnap());
    renderDashboard();
    const btn = screen.getByText(/Frissítés/);
    expect(btn).toBeDisabled();
  });
});


