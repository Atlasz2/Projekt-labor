import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const docs = [];
const project = { activeProjectId: "nagyvazsony" };

vi.mock("../firebaseConfig", () => ({ db: {} }));
vi.mock("../context/ProjectContext", () => ({ useProject: () => project }));
vi.mock("firebase/firestore", () => ({
  collection: (_db, name) => ({ name }),
  doc: (_db, col, id) => ({ col, id }),
  getDocs: vi.fn(async () => ({
    docs: docs.map((d) => ({ id: d.id, data: () => d.data })),
  })),
  addDoc: vi.fn(async () => ({ id: "uj-id" })),
  updateDoc: vi.fn(async () => {}),
  deleteDoc: vi.fn(async () => {}),
}));

import { addDoc, deleteDoc, getDocs, updateDoc } from "firebase/firestore";
import { useFirestoreCollection } from "./useFirestoreCollection";

const mapper = (d) => ({ id: d.id, ...d.data() });

function renderCollection(options) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  return renderHook(() => useFirestoreCollection("events", mapper, options), { wrapper });
}

describe("useFirestoreCollection", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    project.activeProjectId = "nagyvazsony";
    docs.splice(0, docs.length,
      { id: "regi", data: { name: "Régi (projectId nélkül)" } },
      { id: "sajat", data: { name: "Saját", projectId: "nagyvazsony" } },
      { id: "idegen", data: { name: "Idegen", projectId: "tapolca" } },
    );
  });

  it("csak az aktív település elemeit adja; a projectId nélküli az alapértelmezetté", async () => {
    const { result } = renderCollection();
    await waitFor(() => expect(result.current.query.isSuccess).toBe(true));
    expect(result.current.query.data.map((d) => d.id)).toEqual(["regi", "sajat"]);
  });

  it("másik településen csak annak elemei látszanak", async () => {
    project.activeProjectId = "tapolca";
    const { result } = renderCollection();
    await waitFor(() => expect(result.current.query.isSuccess).toBe(true));
    expect(result.current.query.data.map((d) => d.id)).toEqual(["idegen"]);
  });

  it("új elemnél beállítja a projectId-t, meghívja az afterAdd-et, és frissíti a listát", async () => {
    const afterAdd = vi.fn(async () => {});
    const { result } = renderCollection({ afterAdd });
    await waitFor(() => expect(result.current.query.isSuccess).toBe(true));
    await act(() => result.current.add.mutateAsync({ name: "Új", projectId: "tapolca" }));
    expect(addDoc).toHaveBeenCalledWith({ name: "events" }, { name: "Új", projectId: "nagyvazsony" });
    expect(afterAdd).toHaveBeenCalledWith("uj-id", { name: "Új", projectId: "tapolca" });
    await waitFor(() => expect(getDocs).toHaveBeenCalledTimes(2));
  });

  it("módosításnál a projectId az aktív település marad", async () => {
    const { result } = renderCollection();
    await act(() => result.current.update.mutateAsync({ id: "sajat", data: { name: "Átírt" } }));
    expect(updateDoc).toHaveBeenCalledWith(
      { col: "events", id: "sajat" },
      { name: "Átírt", projectId: "nagyvazsony" },
    );
  });

  it("törléskor a megadott dokumentumot törli", async () => {
    const { result } = renderCollection();
    await act(() => result.current.remove.mutateAsync("sajat"));
    expect(deleteDoc).toHaveBeenCalledWith({ col: "events", id: "sajat" });
  });
});
