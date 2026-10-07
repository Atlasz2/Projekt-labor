import { beforeEach, describe, expect, it, vi } from "vitest";

const mockGetDoc = vi.fn();
const mockGetDocs = vi.fn();

vi.mock("firebase/firestore", () => ({
  getDoc: (...args) => mockGetDoc(...args),
  getDocs: (...args) => mockGetDocs(...args),
  collection: vi.fn((db, col) => ({ _col: col })),
  query: vi.fn((col, ...filters) => ({ ...col, filters })),
  where: vi.fn((field, op, value) => [field, op, value]),
  doc: vi.fn((db, col, id) => ({ _col: col, _id: id })),
  serverTimestamp: vi.fn(() => "ts"),
}));

import {
  assertQrCodeAvailable,
  currentQrCode,
  customQrCodeProblem,
  generateQrCode,
  isWeakQrCode,
  loadQrCodesByTarget,
  qrHash,
  qrMappingDocId,
  stageQrDelete,
  stageQrSave,
  QrCodeCollisionError,
  MIN_CUSTOM_QR_LENGTH,
} from "./qrMapping";

const db = {};
const existing = (data) => ({ exists: () => true, data: () => data });
const missing = () => ({ exists: () => false });

// Közös ellenőrző értékek – ugyanezeket várja a Cloud Functions migrációs
// tesztje és a mobil teszt is, így a három implementáció biztosan egyezik.
const HASH_VECTORS = {
  "NV-TEST": "0abb45e3145aaa2aa1615ef649495da944a4ddabf2ab985ab4977df7a6f18c7e",
  "Kinizsi-vár-ÁRVÍZTŰRŐ": "4b0ad59562f24dd4fcdb87acf1aa7e50f8f0520f619b8ba0929bec5da53676c1",
};

function fakeBatch() {
  const ops = [];
  return {
    ops,
    set: (ref, data) => ops.push(["set", ref, data]),
    update: (ref, data) => ops.push(["update", ref, data]),
    delete: (ref) => ops.push(["delete", ref]),
  };
}

describe("qrMappingDocId", () => {
  it("URI-kódolja a kódot, hogy dokumentum-azonosítónak biztonságos legyen", () => {
    expect(qrMappingDocId("VAR-001")).toBe("VAR-001");
    expect(qrMappingDocId("a/b c")).toBe("a%2Fb%20c");
  });
});

describe("generateQrCode", () => {
  it("előtaggal ellátott, 16 jeles, kétértelmű jelek nélküli kódot ad", () => {
    const code = generateQrCode();
    expect(code).toMatch(/^NV-[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{16}$/);
  });

  it("minden hívás más kódot ad, és a kód elég hosszú az egyedi kódokhoz is", () => {
    const codes = new Set(Array.from({ length: 200 }, () => generateQrCode()));
    expect(codes.size).toBe(200);
    expect(generateQrCode().length).toBeGreaterThanOrEqual(MIN_CUSTOM_QR_LENGTH);
  });
});

describe("qrHash", () => {
  it("SHA-256 hex – egyezik a szerver és a mobil ellenőrző értékeivel", async () => {
    for (const [code, hash] of Object.entries(HASH_VECTORS)) {
      expect(await qrHash(code)).toBe(hash);
    }
  });
});

describe("customQrCodeProblem / isWeakQrCode", () => {
  it("üres kódnál nincs probléma (generált kód lesz)", () => {
    expect(customQrCodeProblem("  ")).toBeNull();
  });

  it("a rövid, kitalálható kódot és a perjelet elutasítja", () => {
    expect(customQrCodeProblem("VAR-001")).toMatch(/legalább 12/);
    expect(customQrCodeProblem("VARKERT/2026-01")).toMatch(/„\/”/);
    expect(customQrCodeProblem("VARKERT-2026-TAVASZ")).toBeNull();
  });

  it("gyenge a hiányzó, rövid vagy a dokumentum-azonosítóval egyező kód", () => {
    expect(isWeakQrCode("", "st1")).toBe(true);
    expect(isWeakQrCode("VAR-001", "st1")).toBe(true);
    expect(isWeakQrCode("abcdefghijklmnop", "abcdefghijklmnop")).toBe(true);
    expect(isWeakQrCode(generateQrCode(), "st1")).toBe(false);
  });
});

describe("loadQrCodesByTarget / currentQrCode", () => {
  it("a leképezésből adja a kódot, a migráció előtt a régi mezőből vagy az azonosítóból", async () => {
    mockGetDocs.mockResolvedValueOnce({
      docs: [
        { id: "NV-AAA", data: () => ({ code: "NV-AAA", kind: "station", targetId: "st1" }) },
        { id: "EV%2F1", data: () => ({ kind: "event", targetId: "ev1" }) },
      ],
    });
    const codes = await loadQrCodesByTarget(db, "nagyvazsony");
    expect(mockGetDocs.mock.calls[0][0]).toEqual({ _col: "qr_codes", filters: [["projectId", "==", "nagyvazsony"]] });
    expect(currentQrCode(codes, "station", { id: "st1", qrCode: "REGI" })).toBe("NV-AAA");
    expect(currentQrCode(codes, "event", { id: "ev1" })).toBe("EV/1");
    expect(currentQrCode(codes, "station", { id: "st2", qrCode: "REGI-KOD" })).toBe("REGI-KOD");
    expect(currentQrCode(codes, "station", { id: "st3" })).toBe("st3");
  });
});

describe("assertQrCodeAvailable", () => {
  beforeEach(() => mockGetDoc.mockReset());

  it("szabad kódra és a saját leképezésre nem dob", async () => {
    mockGetDoc.mockResolvedValueOnce(missing());
    await expect(assertQrCodeAvailable(db, { code: "X", kind: "station", targetId: "s1" })).resolves.toBeUndefined();
    mockGetDoc.mockResolvedValueOnce(existing({ kind: "station", targetId: "s1" }));
    await expect(assertQrCodeAvailable(db, { code: "X", kind: "station", targetId: "s1" })).resolves.toBeUndefined();
  });

  it("másik elemhez tartozó kódra, illetve új elemnél QrCodeCollisionError-t dob", async () => {
    mockGetDoc.mockResolvedValueOnce(existing({ kind: "event", targetId: "e9" }));
    await expect(assertQrCodeAvailable(db, { code: "X", kind: "station", targetId: "s1" })).rejects.toBeInstanceOf(QrCodeCollisionError);
    mockGetDoc.mockResolvedValueOnce(existing({ kind: "station", targetId: "s1" }));
    await expect(assertQrCodeAvailable(db, { code: "X", kind: "station", targetId: null })).rejects.toBeInstanceOf(QrCodeCollisionError);
  });

  it("más település (olvasásra tiltott) leképezése ütközésnek számít", async () => {
    mockGetDoc.mockRejectedValueOnce(Object.assign(new Error("denied"), { code: "permission-denied" }));
    await expect(assertQrCodeAvailable(db, { code: "X", kind: "station" })).rejects.toBeInstanceOf(QrCodeCollisionError);
  });

  it("egyéb olvasási hibát továbbad (a leképezés nélkül a mentés nem biztonságos)", async () => {
    mockGetDoc.mockRejectedValueOnce(new Error("unavailable"));
    await expect(assertQrCodeAvailable(db, { code: "X", kind: "station" })).rejects.toThrow("unavailable");
  });
});

describe("stageQrSave / stageQrDelete", () => {
  const ops = { deleteField: () => "DELETE" };
  const ref = { _col: "stations", _id: "st1", id: "st1" };

  it("új elemnél a dokumentum a lenyomatot kapja (kódot nem), a leképezés a kódot", async () => {
    const batch = fakeBatch();
    await stageQrSave(db, {
      batch, ops, kind: "station", targetRef: ref, isNew: true,
      payload: { name: "Vár" }, code: "NV-TEST", previousCode: null, projectId: "nagyvazsony",
    });
    expect(batch.ops).toEqual([
      ["set", ref, { name: "Vár", qrHash: HASH_VECTORS["NV-TEST"] }],
      ["set", { _col: "qr_codes", _id: "NV-TEST" },
        { code: "NV-TEST", kind: "station", targetId: "st1", projectId: "nagyvazsony", updatedAt: "ts" }],
    ]);
  });

  it("szerkesztéskor törli a régi nyilvános qrCode mezőt és a régi leképezést", async () => {
    const batch = fakeBatch();
    await stageQrSave(db, {
      batch, ops, kind: "station", targetRef: ref, isNew: false,
      payload: { name: "Vár" }, code: "NV-TEST", previousCode: "st1", projectId: "nagyvazsony",
    });
    expect(batch.ops[0]).toEqual(["update", ref, { name: "Vár", qrHash: HASH_VECTORS["NV-TEST"], qrCode: "DELETE" }]);
    expect(batch.ops[1]).toEqual(["delete", { _col: "qr_codes", _id: "st1" }]);
    expect(batch.ops[2][0]).toBe("set");
  });

  it("változatlan kódnál nem törli a leképezést", async () => {
    const batch = fakeBatch();
    await stageQrSave(db, {
      batch, ops, kind: "station", targetRef: ref, isNew: false,
      payload: {}, code: "NV-TEST", previousCode: "NV-TEST", projectId: "nagyvazsony",
    });
    expect(batch.ops.filter(([op]) => op === "delete")).toEqual([]);
  });

  it("törléskor az elem és a leképezése ugyanabba a kötegbe kerül", () => {
    const batch = fakeBatch();
    stageQrDelete(db, { batch, targetRef: ref, code: "NV-TEST" });
    expect(batch.ops).toEqual([["delete", ref], ["delete", { _col: "qr_codes", _id: "NV-TEST" }]]);
  });
});
