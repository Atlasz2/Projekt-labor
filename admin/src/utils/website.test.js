import { describe, expect, it } from "vitest";
import { normalizeWebsite, websiteLabel } from "./website";

describe("normalizeWebsite", () => {
  it("üres bemenetre üres sztring", () => {
    expect(normalizeWebsite("  ")).toBe("");
    expect(normalizeWebsite(undefined)).toBe("");
  });

  it("séma nélküli címhez https-t ad", () => {
    expect(normalizeWebsite("www.kinizsietterem.hu")).toBe("https://www.kinizsietterem.hu/");
  });

  it("a teljes http(s) címet megtartja", () => {
    expect(normalizeWebsite("http://pelda.hu/menu?x=1")).toBe("http://pelda.hu/menu?x=1");
  });

  it("nem http(s) sémát és értelmetlen címet elutasít", () => {
    expect(normalizeWebsite("javascript:alert(1)")).toBeNull();
    expect(normalizeWebsite("mailto:info@pelda.hu")).toBeNull();
    expect(normalizeWebsite("nem egy cím")).toBeNull();
  });
});

describe("websiteLabel", () => {
  it("rövid, olvasható alakot ad", () => {
    expect(websiteLabel("https://www.pelda.hu/")).toBe("www.pelda.hu");
  });
});
