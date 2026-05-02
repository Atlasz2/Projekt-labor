import { describe, expect, it } from "vitest";
import { getQrValue, getQrImageUrl } from "./qrHelpers";

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

describe("getQrImageUrl", () => {
  it("encodes the qr value in the url", () => {
    const url = getQrImageUrl("hello world", 200);
    expect(url).toContain("hello%20world");
    expect(url).toContain("200x200");
  });

  it("uses default size 140 when not specified", () => {
    const url = getQrImageUrl("val");
    expect(url).toContain("140x140");
  });

  it("handles empty value gracefully", () => {
    const url = getQrImageUrl("");
    expect(url).toContain("data=");
  });
});
