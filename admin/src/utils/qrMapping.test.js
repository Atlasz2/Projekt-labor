import { beforeEach, describe, expect, it, vi } from "vitest";

const mockGetDoc = vi.fn();
const mockSetDoc = vi.fn();
const mockDeleteDoc = vi.fn();

vi.mock("firebase/firestore", () => ({
  getDoc: (...args) => mockGetDoc(...args),
  setDoc: (...args) => mockSetDoc(...args),
  deleteDoc: (...args) => mockDeleteDoc(...args),
  doc: vi.fn((db, col, id) => ({ _col: col, _id: id })),
  serverTimestamp: vi.fn(() => "ts"),
}));

import {
  assertQrCodeAvailable,
  effectiveQrCode,
  qrMappingDocId,
  removeQrMapping,
  syncQrMapping,
  QrCodeCollisionError,
} from "./qrMapping";

const db = {};
const existing = (data) => ({ exists: () => true, data: () => data });
const missing = () => ({ exists: () => false });

describe("qrMappingDocId", () => {
  it("URI-kódolja a kódot, hogy dokumentum-azonosítónak biztonságos legyen", () => {
    expect(qrMappingDocId("VAR-001")).toBe("VAR-001");
    expect(qrMappingDocId("a/b c")).toBe("a%2Fb%20c");
  });
});

describe("effectiveQrCode", () => {
  it("a kitöltött kódot adja, üresnél a cél id-t", () => {
    expect(effectiveQrCode("VAR-001", "st1")).toBe("VAR-001");
    expect(effectiveQrCode("  ", "st1")).toBe("st1");
    expect(effectiveQrCode(null, "st1")).toBe("st1");
  });
});

describe("assertQrCodeAvailable", () => {
  beforeEach(() => vi.clearAllMocks());

  it("üres kódra nem kérdezi a Firestore-t", async () => {
    await assertQrCodeAvailable(db, { code: "", kind: "station" });
    expect(mockGetDoc).not.toHaveBeenCalled();
  });

  it("szabad kódra nem dob", async () => {
    mockGetDoc.mockResolvedValueOnce(missing());
    await expect(
      assertQrCodeAvailable(db, { code: "VAR-001", kind: "station", targetId: "st1" }),
    ).resolves.toBeUndefined();
  });

  it("saját (azonos cél) leképezésre nem dob", async () => {
    mockGetDoc.mockResolvedValueOnce(
      existing({ kind: "station", targetId: "st1" }),
    );
    await expect(
      assertQrCodeAvailable(db, { code: "VAR-001", kind: "station", targetId: "st1" }),
    ).resolves.toBeUndefined();
  });

  it("másik elemhez tartozó kódra QrCodeCollisionError-t dob", async () => {
    mockGetDoc.mockResolvedValueOnce(
      existing({ kind: "station", targetId: "MASIK" }),
    );
    await expect(
      assertQrCodeAvailable(db, { code: "VAR-001", kind: "station", targetId: "st1" }),
    ).rejects.toBeInstanceOf(QrCodeCollisionError);
  });

  it("új elemnél (targetId nélkül) bármely létező leképezés ütközés", async () => {
    mockGetDoc.mockResolvedValueOnce(
      existing({ kind: "event", targetId: "ev9" }),
    );
    await expect(
      assertQrCodeAvailable(db, { code: "EVENT-1", kind: "event" }),
    ).rejects.toBeInstanceOf(QrCodeCollisionError);
  });

  it("a qr_codes olvasás hibáján NEM dob (nem blokkolja a mentést)", async () => {
    // pl. a firestore.rules még nincs deployolva -> permission-denied
    mockGetDoc.mockRejectedValueOnce(new Error("permission-denied"));
    await expect(
      assertQrCodeAvailable(db, { code: "VAR-001", kind: "station", targetId: "st1" }),
    ).resolves.toBeUndefined();
  });
});

describe("syncQrMapping", () => {
  beforeEach(() => vi.clearAllMocks());

  it("beírja a leképezést a kód szerinti doc-id alá", async () => {
    await syncQrMapping(db, { kind: "station", targetId: "st1", code: "VAR-001" });

    expect(mockSetDoc).toHaveBeenCalledWith(
      expect.objectContaining({ _col: "qr_codes", _id: "VAR-001" }),
      expect.objectContaining({ code: "VAR-001", kind: "station", targetId: "st1" }),
    );
    expect(mockDeleteDoc).not.toHaveBeenCalled();
  });

  it("kódváltásnál törli a régi leképezést", async () => {
    await syncQrMapping(db, {
      kind: "station",
      targetId: "st1",
      code: "UJ-KOD",
      previousCode: "REGI-KOD",
    });

    expect(mockDeleteDoc).toHaveBeenCalledWith(
      expect.objectContaining({ _col: "qr_codes", _id: "REGI-KOD" }),
    );
    expect(mockSetDoc).toHaveBeenCalledWith(
      expect.objectContaining({ _id: "UJ-KOD" }),
      expect.anything(),
    );
  });

  it("változatlan kódnál nem töröl", async () => {
    await syncQrMapping(db, {
      kind: "station",
      targetId: "st1",
      code: "VAR-001",
      previousCode: "VAR-001",
    });
    expect(mockDeleteDoc).not.toHaveBeenCalled();
  });

  it("üres kódnál a cél id lesz a leképezés kulcsa", async () => {
    await syncQrMapping(db, { kind: "event", targetId: "ev1", code: "" });
    expect(mockSetDoc).toHaveBeenCalledWith(
      expect.objectContaining({ _id: "ev1" }),
      expect.objectContaining({ code: "ev1", kind: "event" }),
    );
  });
});

describe("removeQrMapping", () => {
  beforeEach(() => vi.clearAllMocks());

  it("törli a leképezést az effektív kód alapján", async () => {
    await removeQrMapping(db, { code: "VAR-001", targetId: "st1" });
    expect(mockDeleteDoc).toHaveBeenCalledWith(
      expect.objectContaining({ _col: "qr_codes", _id: "VAR-001" }),
    );
  });

  it("üres kódnál a cél id alapján töröl", async () => {
    await removeQrMapping(db, { code: "", targetId: "st1" });
    expect(mockDeleteDoc).toHaveBeenCalledWith(
      expect.objectContaining({ _id: "st1" }),
    );
  });
});
