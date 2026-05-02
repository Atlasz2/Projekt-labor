import { describe, expect, it } from "vitest";
import { safeString } from "./safeString";

describe("safeString", () => {
  it("returns empty string for nullish values", () => {
    expect(safeString(null)).toBe("");
    expect(safeString(undefined)).toBe("");
  });

  it("returns empty string for objects", () => {
    expect(safeString({ value: "x" })).toBe("");
    expect(safeString(["x"])).toBe("");
  });

  it("trims scalar values", () => {
    expect(safeString("  hello  ")).toBe("hello");
    expect(safeString(42)).toBe("42");
    expect(safeString(true)).toBe("true");
  });

  it("returns empty string for empty string", () => {
    expect(safeString("")).toBe("");
  });

  it("handles zero correctly", () => {
    expect(safeString(0)).toBe("0");
  });

  it("handles false correctly", () => {
    expect(safeString(false)).toBe("false");
  });

  it("returns empty string for NaN", () => {
    expect(safeString(NaN)).toBe("NaN");
  });

  it("handles whitespace-only string", () => {
    expect(safeString("   ")).toBe("");
  });
});
