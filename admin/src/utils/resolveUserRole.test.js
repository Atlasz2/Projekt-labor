import { beforeEach, describe, expect, it, vi } from "vitest";
import { resolveUserRole } from "./resolveUserRole";

// Mock the Firebase config (just needs a db reference object)
vi.mock("../firebaseConfig", () => ({ db: {} }));

// Capture mock functions so tests can control their return values
const mockGetDoc = vi.fn();
const mockGetDocs = vi.fn();

vi.mock("firebase/firestore", () => ({
  getDoc: (...args) => mockGetDoc(...args),
  getDocs: (...args) => mockGetDocs(...args),
  doc: vi.fn((db, col, id) => ({ _col: col, _id: id })),
  collection: vi.fn(),
  query: vi.fn(),
  where: vi.fn(),
  limit: vi.fn(),
}));

/** Convenience: build a fake DocumentSnapshot */
const fakeDoc = (data) => ({ exists: () => true, data: () => data });
const missingDoc = () => ({ exists: () => false });

describe("resolveUserRole", () => {
  beforeEach(() => vi.clearAllMocks());

  it("returns 'user' for null input without touching Firestore", async () => {
    expect(await resolveUserRole(null)).toBe("user");
    expect(mockGetDoc).not.toHaveBeenCalled();
  });

  it("returns role from uid-based doc", async () => {
    mockGetDoc.mockResolvedValueOnce(fakeDoc({ role: "admin" }));
    expect(await resolveUserRole({ uid: "u1", email: "a@b.com" })).toBe("admin");
  });

  it("normalises role to lowercase", async () => {
    mockGetDoc.mockResolvedValueOnce(fakeDoc({ role: "Admin" }));
    expect(await resolveUserRole({ uid: "u1", email: "" })).toBe("admin");
  });

  it("defaults to 'user' when uid doc has no role field", async () => {
    mockGetDoc.mockResolvedValueOnce(fakeDoc({}));
    expect(await resolveUserRole({ uid: "u1", email: "" })).toBe("user");
  });

  it("falls back to email doc when uid doc is absent", async () => {
    mockGetDoc
      .mockResolvedValueOnce(missingDoc())            // uid lookup: not found
      .mockResolvedValueOnce(fakeDoc({ role: "admin" })); // email doc: found
    expect(await resolveUserRole({ uid: "u1", email: "admin@test.com" })).toBe("admin");
  });

  it("skips email lookup when email is empty", async () => {
    mockGetDoc.mockResolvedValueOnce(missingDoc());
    expect(await resolveUserRole({ uid: "u1", email: "" })).toBe("user");
    expect(mockGetDoc).toHaveBeenCalledTimes(1);
  });

  it("falls back to query when uid and email doc both absent", async () => {
    mockGetDoc.mockResolvedValue(missingDoc());
    mockGetDocs.mockResolvedValueOnce({
      empty: false,
      docs: [{ data: () => ({ role: "admin" }) }],
    });
    expect(await resolveUserRole({ uid: "u1", email: "admin@test.com" })).toBe("admin");
  });

  it("returns 'user' when all three lookups find nothing", async () => {
    mockGetDoc.mockResolvedValue(missingDoc());
    mockGetDocs.mockResolvedValueOnce({ empty: true, docs: [] });
    expect(await resolveUserRole({ uid: "u1", email: "none@test.com" })).toBe("user");
  });

  it("returns 'user' on Firestore error (graceful fallback)", async () => {
    mockGetDoc.mockRejectedValue(new Error("Firestore unavailable"));
    expect(await resolveUserRole({ uid: "u1", email: "a@b.com" })).toBe("user");
  });
});
