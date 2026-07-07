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
  doc: vi.fn(),
  setDoc: vi.fn().mockResolvedValue(undefined),
  orderBy: vi.fn(),
  limit: vi.fn(),
  getCountFromServer: vi.fn().mockResolvedValue({ data: () => ({ count: 0 }) }),
  getAggregateFromServer: vi.fn().mockResolvedValue({ data: () => ({ total: 0, n: 0 }) }),
  sum: vi.fn(),
  count: vi.fn(),
}));

import { getDocs, getCountFromServer, getAggregateFromServer } from "firebase/firestore";

const makeSnap = (size = 0, docs = []) => ({ docs, size });
const makeProgressSnap = (points = []) => ({
  docs: points.map((p) => ({ data: () => ({ totalPoints: p }) })),
  size: points.length,
});

// Counts/sum are now server-side aggregations; getDocs is only used for
// trips, stations, achievements, the top-5 players, and the trend read (in that order).
const mockAggregates = (usersTotal = 2, pointsTotal = 300, tracked = 2) => {
  getCountFromServer.mockResolvedValue({ data: () => ({ count: usersTotal }) });
  getAggregateFromServer.mockResolvedValue({ data: () => ({ total: pointsTotal, n: tracked }) });
};

const mockSuccess = () => {
  mockAggregates();
  getDocs
    .mockResolvedValueOnce(makeSnap(3))                     // trips
    .mockResolvedValueOnce(makeSnap(5))                     // stations
    .mockResolvedValueOnce({ docs: [], size: 0 })          // achievements
    .mockResolvedValueOnce(makeProgressSnap([200, 100]))   // top players
    .mockResolvedValueOnce({ docs: [], size: 0 });         // stats_daily trend read
};

// Like mockSuccess, but the stats_daily read returns two snapshots (newest-first,
// matching the orderBy('date','desc') query the component reverses into chronological order).
const mockSuccessWithTrend = () => {
  mockAggregates();
  getDocs
    .mockResolvedValueOnce(makeSnap(3))
    .mockResolvedValueOnce(makeSnap(5))
    .mockResolvedValueOnce({ docs: [], size: 0 })
    .mockResolvedValueOnce(makeProgressSnap([200, 100]))
    .mockResolvedValueOnce({
      docs: [
        { data: () => ({ date: "2026-06-14", totalPoints: 777, users: 9, stations: 5 }) },
        { data: () => ({ date: "2026-06-13", totalPoints: 500, users: 4, stations: 5 }) },
      ],
      size: 2,
    });
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

  it("renders the trend with the latest snapshot value and switches metric", async () => {
    mockSuccessWithTrend();
    renderDashboard();

    // Default metric = totalPoints; latest snapshot value is 777.
    await waitFor(() => expect(screen.getByText("📈 Trend")).toBeInTheDocument());
    expect(screen.getByText("777")).toBeInTheDocument();

    // Switching to the "Felhasználók" metric shows its latest value (9).
    await userEvent.click(screen.getByRole("button", { name: "Felhasználók" }));
    expect(screen.getByText("9")).toBeInTheDocument();
  });

  it("shows the trend-building hint when fewer than two snapshots exist", async () => {
    mockSuccess(); // stats_daily read returns []
    renderDashboard();
    await waitFor(() => expect(screen.getByText("📈 Trend")).toBeInTheDocument());
    expect(screen.getByText(/A trend épül/)).toBeInTheDocument();
  });
});


