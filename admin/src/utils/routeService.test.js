import { describe, expect, it } from "vitest";
import {
  formatDistance,
  formatDuration,
  getStoredRouteCoordinates,
} from "./routeService";

describe("formatDistance", () => {
  it("converts metres to km with one decimal", () => {
    expect(formatDistance(3500)).toBe("3.5 km");
  });

  it("returns N/A for zero", () => {
    expect(formatDistance(0)).toBe("N/A");
  });

  it("returns N/A for undefined", () => {
    expect(formatDistance(undefined)).toBe("N/A");
  });

  it("returns N/A for negative value", () => {
    expect(formatDistance(-100)).toBe("N/A");
  });
});

describe("formatDuration", () => {
  it("shows hours and minutes", () => {
    expect(formatDuration(5400)).toBe("1 o 30 p");
  });

  it("shows only minutes for < 1 hour", () => {
    expect(formatDuration(900)).toBe("15 p");
  });

  it("rounds to at least 1 minute", () => {
    expect(formatDuration(10)).toBe("1 p");
  });

  it("returns N/A for zero", () => {
    expect(formatDuration(0)).toBe("N/A");
  });

  it("returns N/A for undefined", () => {
    expect(formatDuration(undefined)).toBe("N/A");
  });
});


describe("getStoredRouteCoordinates", () => {
  it("a túrához elmentett útvonalat adja vissza", () => {
    const trip = { routeCoordinates: [[47.1, 17.6], [47.2, 17.7]] };
    expect(getStoredRouteCoordinates(trip)).toEqual([[47.1, 17.6], [47.2, 17.7]]);
  });

  it("GeoJSON geometry esetén megfordítja a sorrendet", () => {
    const trip = { geometry: { coordinates: [[17.6, 47.1], [17.7, 47.2]] } };
    expect(getStoredRouteCoordinates(trip)).toEqual([[47.1, 17.6], [47.2, 17.7]]);
  });

  it("üres tömböt ad, ha nincs mentett útvonal", () => {
    expect(getStoredRouteCoordinates({})).toEqual([]);
    expect(getStoredRouteCoordinates(null)).toEqual([]);
  });
});
