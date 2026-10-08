import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import Stations from "./Stations";

// ── Mocks ──────────────────────────────────────────────────────────────────
vi.mock("../firebaseConfig", () => ({ db: {}, storage: {} }));
vi.mock("../styles/Stations.css", () => ({}));

// Az aktív projekt fix – a szűrés a valós filterByProject-tel fut (a projectId
// nélküli seed-dokumentumok az alapértelmezett projektbe tartoznak).
vi.mock("../context/ProjectContext", () => ({
  useProject: () => ({
    activeProjectId: "nagyvazsony",
    projects: [{ id: "nagyvazsony", name: "Nagyvázsony" }],
    setActiveProjectId: vi.fn(),
    createProject: vi.fn(),
  }),
}));

// A mentés és a törlés egy kötegben (writeBatch) írja az állomást és a
// QR-leképezést; a köteg műveleteit a `batchOps` gyűjti.
const batchOps = [];
vi.mock("firebase/firestore", () => ({
  collection: vi.fn((_db, name) => name),
  query: vi.fn((col) => col),
  where: vi.fn(() => null),
  getDocs: vi.fn(),
  getDoc: vi.fn(async () => ({ exists: () => false })),
  deleteField: vi.fn(() => "DELETE_FIELD"),
  serverTimestamp: vi.fn(() => "TS"),
  doc: vi.fn((_db, col, id) => ({ _col: col, _id: id ?? "uj-id", id: id ?? "uj-id" })),
  writeBatch: vi.fn(() => ({
    set: (ref, data) => batchOps.push(["set", ref, data]),
    update: (ref, data) => batchOps.push(["update", ref, data]),
    delete: (ref) => batchOps.push(["delete", ref]),
    commit: vi.fn(async () => {}),
  })),
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
  buildPhotoFields: vi.fn(() => ({ photos: [], photoUrls: [], imageUrl: "" })),
}));
vi.mock("../utils/qrHelpers", () => ({
  qrDataUrl: vi.fn(async () => "data:image/png;base64,"),
}));

import { getDocs } from "firebase/firestore";

const makeStation = (overrides = {}) => ({
  id: "s1",
  name: "Teszt állomás",
  description: "Leírás",
  points: 10,
  latitude: 47.06,
  longitude: 17.715,
  tripIds: ["t1"],
  photos: [],
  qrCode: "QR123",
  ...overrides,
});

const makeSnap = (items) => ({
  docs: items.map((item) => ({ id: item.id, data: () => item })),
});

// Route getDocs by collection name so the stations grid and the trip-filter
// dropdown (populated from the trips collection) get distinct data sets.
const setData = (stationItems, tripItems = [], qrMappings = []) =>
  getDocs.mockImplementation((col) =>
    Promise.resolve(
      col === "qr_codes"
        ? { docs: qrMappings.map((m) => ({ id: m.code, data: () => m })) }
        : makeSnap(col === "trips" ? tripItems : stationItems),
    )
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

    expect(await screen.findByText("Új állomás")).toBeInTheDocument();
    const checkbox = document.querySelector(".trip-membership-item input[type='checkbox']");
    expect(checkbox.checked).toBe(true);
  });

  it("a state editor allows checking multiple trip memberships for one station", async () => {
    setData(
      [makeStation({ id: "s1", name: "Vár állomás", tripIds: ["t1"] })],
      [
        { id: "t1", name: "Rövid túra" },
        { id: "t2", name: "Hosszú túra" },
      ]
    );
    renderStations(mkClient(), ["/stations?edit=s1"]);

    expect(await screen.findByText("Állomás szerkesztése")).toBeInTheDocument();
    const checkboxes = document.querySelectorAll(".trip-membership-item input[type='checkbox']");
    expect(checkboxes).toHaveLength(2);
    expect(checkboxes[0].checked).toBe(true); // t1 már tagság
    expect(checkboxes[1].checked).toBe(false); // t2 még nem

    await userEvent.click(checkboxes[1]);
    expect(checkboxes[0].checked).toBe(true);
    expect(checkboxes[1].checked).toBe(true);
  });

  it("?edit deep-link opens the editor prefilled for that station", async () => {
    setData([makeStation({ id: "s1", name: "Vár állomás" })]);
    renderStations(mkClient(), ["/stations?edit=s1"]);

    expect(await screen.findByText("Állomás szerkesztése")).toBeInTheDocument();
    const nameInput = document.querySelector('.station-editor-shell input[type="text"]');
    expect(nameInput.value).toBe("Vár állomás");
  });

  describe("mentés a QR-leképezéssel egy kötegben", () => {
    beforeEach(() => {
      batchOps.length = 0;
    });

    const openEditorAndSave = async (prepare) => {
      renderStations();
      await screen.findByText("Teszt állomás");
      await userEvent.click(screen.getByRole("button", { name: /Szerkesztés/ }));
      if (prepare) await prepare();
      await userEvent.click(screen.getByRole("button", { name: "Mentés" }));
      await waitFor(() => expect(batchOps.length).toBeGreaterThan(0));
    };

    it("a nyilvános dokumentumba csak a lenyomat kerül, a régi qrCode mező törlődik", async () => {
      setData([makeStation({ qrCode: "VARKERT-2026-TAVASZ" })]);
      await openEditorAndSave();

      const [op, ref, data] = batchOps[0];
      expect(op).toBe("update");
      expect(ref._id).toBe("s1");
      expect(data.qrCode).toBe("DELETE_FIELD");
      expect(data.qrHash).toMatch(/^[0-9a-f]{64}$/);
      const mapping = batchOps.find(([o, r]) => o === "set" && r._col === "qr_codes");
      expect(mapping[2]).toMatchObject({
        code: "VARKERT-2026-TAVASZ", kind: "station", targetId: "s1", projectId: "nagyvazsony",
      });
    });

    it("a leképezésben tárolt kódot tartja meg, és a gyenge kódra figyelmeztet", async () => {
      setData([makeStation({ qrCode: undefined })], [], [
        { code: "s1", kind: "station", targetId: "s1", projectId: "nagyvazsony" },
      ]);
      renderStations();
      await screen.findByText("Teszt állomás");
      await userEvent.click(screen.getByRole("button", { name: /Szerkesztés/ }));
      expect(screen.getByLabelText("QR-kód")).toHaveValue("s1");
      expect(screen.getByText(/Ez a kód kitalálható/)).toBeInTheDocument();
    });

    it("új véletlen kód generálásakor a régi leképezés törlődik", async () => {
      setData([makeStation({ qrCode: "VARKERT-2026-TAVASZ" })]);
      await openEditorAndSave(() =>
        userEvent.click(screen.getByRole("button", { name: "Új véletlen kód" })),
      );

      expect(batchOps).toContainEqual(["delete", expect.objectContaining({ _col: "qr_codes", _id: "VARKERT-2026-TAVASZ" })]);
      const mapping = batchOps.find(([o, r]) => o === "set" && r._col === "qr_codes");
      expect(mapping[2].code).toMatch(/^NV-[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{16}$/);
    });

    it("a rövid egyedi kódot nem menti", async () => {
      setData([makeStation({ qrCode: "VARKERT-2026-TAVASZ" })]);
      renderStations();
      await screen.findByText("Teszt állomás");
      await userEvent.click(screen.getByRole("button", { name: /Szerkesztés/ }));
      const input = screen.getByLabelText("QR-kód");
      await userEvent.clear(input);
      await userEvent.type(input, "VAR-1");
      await userEvent.click(screen.getByRole("button", { name: "Mentés" }));
      expect(await screen.findByText(/legalább 12 karakter/)).toBeInTheDocument();
      expect(batchOps).toEqual([]);
    });

    it("alapból kötelező a helymeghatározás", async () => {
      setData([makeStation({ qrCode: "VARKERT-2026-TAVASZ" })]);
      await openEditorAndSave();
      expect(batchOps[0][2].requireLocation).toBe(true);
    });

    it("a pozíció nélküli beváltás kifejezetten engedélyezhető", async () => {
      setData([makeStation({ qrCode: "VARKERT-2026-TAVASZ" })]);
      await openEditorAndSave(() =>
        userEvent.click(screen.getByLabelText(/Helymeghatározás nélkül is beváltható/)),
      );
      expect(batchOps[0][2].requireLocation).toBe(false);
    });
  });
});
