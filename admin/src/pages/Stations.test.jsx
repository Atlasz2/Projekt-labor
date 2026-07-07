import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import Stations from "./Stations";

// ── Mocks ──────────────────────────────────────────────────────────────────
vi.mock("../firebaseConfig", () => ({ db: {}, storage: {} }));
vi.mock("../styles/Stations.css", () => ({}));

vi.mock("firebase/firestore", () => ({
  collection: vi.fn((_db, name) => name),
  getDocs: vi.fn(),
  addDoc: vi.fn().mockResolvedValue({ id: "new1" }),
  updateDoc: vi.fn().mockResolvedValue(undefined),
  deleteDoc: vi.fn().mockResolvedValue(undefined),
  doc: vi.fn((_db, _col, id) => ({ _id: id })),
}));

vi.mock("@react-google-maps/api", () => ({
  GoogleMap: () => <div data-testid="google-map" />,
  Marker: () => null,
  useLoadScript: () => ({ isLoaded: true, loadError: null }),
}));

vi.mock("jspdf", () => ({ jsPDF: vi.fn(() => ({ text: vi.fn(), save: vi.fn(), addImage: vi.fn() })) }));
vi.mock("../utils/imageUpload", () => ({
  uploadImageWithFallback: vi.fn().mockResolvedValue("https://img.test/photo.jpg"),
  fetchDataUrl: vi.fn().mockResolvedValue("data:image/png;base64,abc"),
}));
vi.mock("../utils/photoHelpers", () => ({
  normalizePhotosFromDoc: vi.fn(() => []),
}));
vi.mock("../utils/qrHelpers", () => ({
  getQrValue: vi.fn(() => "QR123"),
  getQrImageUrl: vi.fn(() => ""),
}));

import { getDocs } from "firebase/firestore";

const makeStation = (overrides = {}) => ({
  id: "s1",
  name: "Teszt állomás",
  description: "Leírás",
  points: 10,
  latitude: 47.06,
  longitude: 17.715,
  tripId: "t1",
  photos: [],
  qrCode: "QR123",
  ...overrides,
});

const makeSnap = (items) => ({
  docs: items.map((item) => ({ id: item.id, data: () => item })),
});

// Route getDocs by collection name so the stations grid and the trip-filter
// dropdown (populated from the trips collection) get distinct data sets.
const setData = (stationItems, tripItems = []) =>
  getDocs.mockImplementation((col) =>
    Promise.resolve(makeSnap(col === "trips" ? tripItems : stationItems))
  );

const mkClient = () =>
  new QueryClient({ defaultOptions: { queries: { retry: false } } });

const renderStations = (client = mkClient(), initialEntries = ["/"]) =>
  render(
    <MemoryRouter initialEntries={initialEntries}>
      <QueryClientProvider client={client}>
        <Stations />
      </QueryClientProvider>
    </MemoryRouter>
  );

describe("Stations", () => {
  beforeEach(() => { vi.clearAllMocks(); });

  it("shows loading StateCard while fetching", () => {
    getDocs.mockReturnValue(new Promise(() => {})); // never resolves
    renderStations();
    expect(screen.getByText("Állomások betöltése...")).toBeInTheDocument();
  });

  it("shows empty StateCard when no stations", async () => {
    setData([]);
    renderStations();
    await waitFor(() =>
      expect(screen.getByText("Nincsenek még állomások")).toBeInTheDocument()
    );
  });

  it("shows station name after load", async () => {
    setData([makeStation()]);
    renderStations();
    await waitFor(() => expect(screen.getByText("Teszt állomás")).toBeInTheDocument());
  });

  it("renders the placeholder instead of an empty-src cover img when no photo", async () => {
    setData([makeStation()]);
    renderStations();
    await waitFor(() => expect(screen.getByText("Teszt állomás")).toBeInTheDocument());
    // normalizePhotosFromDoc is mocked to [] → cover falls back to the 📷 placeholder
    expect(screen.getByText("📷")).toBeInTheDocument();
  });

  it("shows multiple station names", async () => {
    setData([
      makeStation({ id: "s1", name: "Állomás A" }),
      makeStation({ id: "s2", name: "Állomás B" }),
    ]);
    renderStations();
    await waitFor(() => {
      expect(screen.getByText("Állomás A")).toBeInTheDocument();
      expect(screen.getByText("Állomás B")).toBeInTheDocument();
    });
  });

  it("search filters visible stations", async () => {
    setData([
      makeStation({ id: "s1", name: "Vár" }),
      makeStation({ id: "s2", name: "Malom" }),
    ]);
    renderStations();
    await waitFor(() => expect(screen.getByText("Vár")).toBeInTheDocument());
    const searchInput = screen.getByPlaceholderText(/Keresés/);
    await userEvent.type(searchInput, "vár");
    expect(screen.getByText("Vár")).toBeInTheDocument();
    expect(screen.queryByText("Malom")).not.toBeInTheDocument();
  });

  it("shows search-empty StateCard when no match", async () => {
    setData([makeStation({ id: "s1", name: "Vár" })]);
    renderStations();
    await waitFor(() => expect(screen.getByText("Vár")).toBeInTheDocument());
    const searchInput = screen.getByPlaceholderText(/Keresés/);
    await userEvent.type(searchInput, "xxxxxxxxx");
    await waitFor(() =>
      expect(screen.getByText("Nincs találat")).toBeInTheDocument()
    );
  });

  it("Keresés törlése CTA clears search", async () => {
    setData([makeStation({ id: "s1", name: "Vár" })]);
    renderStations();
    await waitFor(() => expect(screen.getByText("Vár")).toBeInTheDocument());
    const searchInput = screen.getByPlaceholderText(/Keresés/);
    await userEvent.type(searchInput, "xxxxxxxxx");
    await waitFor(() => expect(screen.getByText("Keresés törlése")).toBeInTheDocument());
    await userEvent.click(screen.getByText("Keresés törlése"));
    expect(screen.getByText("Vár")).toBeInTheDocument();
  });

  it("?addForTrip deep-link opens the add modal preselected to that trip", async () => {
    setData([], [{ id: "t1", name: "Túra 1" }]);
    renderStations(mkClient(), ["/stations?addForTrip=t1"]);

    expect(await screen.findByText("➕ Új állomás")).toBeInTheDocument();
    const modalSelect = document.querySelector(".station-modal select");
    expect(modalSelect.value).toBe("t1");
  });

  it("?edit deep-link opens the editor prefilled for that station", async () => {
    setData([makeStation({ id: "s1", name: "Vár állomás" })]);
    renderStations(mkClient(), ["/stations?edit=s1"]);

    expect(await screen.findByText("✏️ Állomás szerkesztése")).toBeInTheDocument();
    const nameInput = document.querySelector('.station-modal input[type="text"]');
    expect(nameInput.value).toBe("Vár állomás");
  });
});

