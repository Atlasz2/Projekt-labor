import { beforeEach, afterEach, describe, expect, it, vi } from "vitest";

// A firebaseConfig és a CSS mockolása, hogy az Events.jsx importja ne
// próbáljon valódi Firebase-t vagy stílust betölteni.
vi.mock("../firebaseConfig", () => ({ db: {}, storage: {} }));
vi.mock("../styles/Content.css", () => ({}));

import { isPastEvent } from "./Events";

const iso = (d) => d.toISOString().slice(0, 10);

describe("isPastEvent", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-07-23T10:00:00"));
  });
  afterEach(() => vi.useRealTimers());

  it("a tegnapi eseményt múltbelinek jelöli", () => {
    expect(isPastEvent({ date: "2026-07-22" })).toBe(true);
  });

  it("a mai eseményt NEM tekinti múltbelinek", () => {
    expect(isPastEvent({ date: "2026-07-23" })).toBe(false);
  });

  it("a jövőbeli eseményt NEM tekinti múltbelinek", () => {
    expect(isPastEvent({ date: "2026-08-01" })).toBe(false);
  });

  it("üres vagy hiányzó dátumot nem tekint múltbelinek", () => {
    expect(isPastEvent({ date: "" })).toBe(false);
    expect(isPastEvent({})).toBe(false);
  });

  it("érvénytelen dátumot nem tekint múltbelinek", () => {
    expect(isPastEvent({ date: "nem-datum" })).toBe(false);
  });

  it("egy éve lévő eseményekkel is konzisztens", () => {
    const lastYear = new Date();
    lastYear.setFullYear(lastYear.getFullYear() - 1);
    expect(isPastEvent({ date: iso(lastYear) })).toBe(true);
  });
});
