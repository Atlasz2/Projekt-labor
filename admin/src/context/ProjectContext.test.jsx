import { act, renderHook, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

// Memóriabeli „Firestore”: dokumentumok útvonal szerint.
const store = new Map();
const auth = { userRole: "developer", userUid: "dev1" };
const usage = { result: [] };

vi.mock("../firebaseConfig", () => ({ db: {} }));
vi.mock("./AdminAuthContext", () => ({ useAdminAuth: () => auth }));
vi.mock("../utils/projectUsage", async () => {
  const actual = await vi.importActual("../utils/projectUsage");
  return { ...actual, projectUsage: vi.fn(async () => usage.result) };
});
vi.mock("firebase/firestore", () => ({
  collection: (_db, name) => ({ collection: name }),
  doc: (_db, col, id) => ({ path: `${col}/${id}`, id }),
  getDoc: vi.fn(async (ref) => ({
    exists: () => store.has(ref.path),
    data: () => store.get(ref.path),
  })),
  getDocs: vi.fn(async ({ collection }) => ({
    docs: [...store.entries()]
      .filter(([path]) => path.startsWith(`${collection}/`))
      .map(([path, data]) => ({ id: path.split("/")[1], data: () => data })),
  })),
  setDoc: vi.fn(async (ref, data, opts) => {
    store.set(ref.path, opts?.merge ? { ...store.get(ref.path), ...data } : data);
  }),
  deleteDoc: vi.fn(async (ref) => store.delete(ref.path)),
  serverTimestamp: () => "ts",
}));

import { setDoc, deleteDoc } from "firebase/firestore";
import { ProjectProvider, useProject } from "./ProjectContext";

const wrapper = ({ children }) => <ProjectProvider>{children}</ProjectProvider>;

async function renderProject() {
  const hook = renderHook(() => useProject(), { wrapper });
  await waitFor(() => expect(hook.result.current.loading).toBe(false));
  return hook;
}

describe("ProjectContext – településkezelés", () => {
  beforeEach(() => {
    store.clear();
    vi.clearAllMocks();
    usage.result = [];
    auth.userRole = "developer";
    auth.userUid = "dev1";
    localStorage.clear();
    store.set("projects/tapolca", { name: "Tapolca" });
  });

  it("az alapértelmezett település mindig elöl szerepel", async () => {
    const { result } = await renderProject();
    expect(result.current.projects.map((p) => p.id)).toEqual(["nagyvazsony", "tapolca"]);
  });

  it("új település létrehozása után az lesz az aktív", async () => {
    const { result } = await renderProject();
    await act(() => result.current.createProject("Zánka"));
    expect(store.get("projects/zanka")).toMatchObject({ name: "Zánka", isActive: true });
    expect(result.current.activeProjectId).toBe("zanka");
  });

  it("már létező azonosítóval nem hoz létre (nem írja felül a meglévőt)", async () => {
    const { result } = await renderProject();
    await expect(result.current.createProject("Tapolca")).rejects.toThrow(/Már létezik/);
    await expect(result.current.createProject("Nagyvázsony")).rejects.toThrow(/Már létezik/);
    expect(setDoc).not.toHaveBeenCalled();
  });

  it("az alapértelmezett település átnevezése is látszik a listában", async () => {
    const { result } = await renderProject();
    await act(() => result.current.renameProject("nagyvazsony", "Nagyvázsony község"));
    expect(result.current.projects[0]).toMatchObject({ id: "nagyvazsony", name: "Nagyvázsony község" });
    expect(result.current.activeProject.name).toBe("Nagyvázsony község");
  });

  it("üres névre nem nevez át", async () => {
    const { result } = await renderProject();
    await expect(result.current.renameProject("tapolca", "   ")).rejects.toThrow(/kötelező/);
    expect(setDoc).not.toHaveBeenCalled();
  });

  it("az alapértelmezett település nem törölhető", async () => {
    const { result } = await renderProject();
    await expect(result.current.deleteProject("nagyvazsony")).rejects.toThrow(/nem törölhető/);
    expect(deleteDoc).not.toHaveBeenCalled();
  });

  it("nem üres település törlése elmarad, az ok felsorolásával", async () => {
    usage.result = [
      { collection: "trips", label: "túra", count: 3 },
      { collection: "users", label: "hozzárendelt admin", count: 1 },
      { collection: "events", label: "rendezvény", count: 0 },
    ];
    const { result } = await renderProject();
    await expect(result.current.deleteProject("tapolca")).rejects.toThrow(
      "A település nem törölhető, mert még hozzá tartozik: 3 túra, 1 hozzárendelt admin.",
    );
    expect(store.has("projects/tapolca")).toBe(true);
  });

  it("üres település törlésekor az aktív település visszaáll az alapértelmezettre", async () => {
    const { result } = await renderProject();
    act(() => result.current.setActiveProjectId("tapolca"));
    expect(result.current.activeProjectId).toBe("tapolca");
    await act(() => result.current.deleteProject("tapolca"));
    expect(store.has("projects/tapolca")).toBe(false);
    expect(result.current.activeProjectId).toBe("nagyvazsony");
    expect(result.current.projects.map((p) => p.id)).toEqual(["nagyvazsony"]);
  });

  it("a sima admin a hozzárendelt településén dolgozik, és nem válthat", async () => {
    auth.userRole = "admin";
    auth.userUid = "admin1";
    store.set("users/admin1", { projectId: "tapolca" });
    const { result } = await renderProject();
    await waitFor(() => expect(result.current.activeProjectId).toBe("tapolca"));
    expect(result.current.canSwitchProject).toBe(false);
    act(() => result.current.setActiveProjectId("nagyvazsony"));
    expect(result.current.activeProjectId).toBe("tapolca");
  });
});
