import { describe, expect, it } from "vitest";
import { getQrValue, qrDataUrl } from "./qrHelpers";

describe("getQrValue", () => {
  it("returns qrCode when present", () => {
    expect(getQrValue({ qrCode: "ABC123", id: "doc1" })).toBe("ABC123");
  });

  it("falls back to id when qrCode is absent", () => {
    expect(getQrValue({ id: "doc1" })).toBe("doc1");
  });

  it("falls back to id when qrCode is empty string", () => {
    expect(getQrValue({ qrCode: "", id: "doc2" })).toBe("doc2");
  });
});

describe("qrDataUrl", () => {
  it("helyben PNG data URL-t állít elő (nincs külső hívás)", async () => {
    const url = await qrDataUrl("VAR-001", 200);
    expect(url.startsWith("data:image/png;base64,")).toBe(true);
  });

  it("különböző értékekhez különböző kódot ad", async () => {
    expect(await qrDataUrl("A-1")).not.toBe(await qrDataUrl("B-2"));
  });

  it("üres értékre hibával tér vissza (a QrImage ezt üres helyként jeleníti meg)", async () => {
    await expect(qrDataUrl("")).rejects.toThrow();
  });
});
