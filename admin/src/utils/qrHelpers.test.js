import { describe, expect, it } from "vitest";
import { qrDataUrl } from "./qrHelpers";

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
