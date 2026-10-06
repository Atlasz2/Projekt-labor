import { describe, expect, it, vi } from "vitest";

vi.mock("firebase/firestore", () => ({
  collection: vi.fn((_db, name) => ({ name })),
  where: vi.fn(() => ({})),
  query: vi.fn((col) => col),
  getCountFromServer: vi.fn(async (q) => ({
    data: () => ({ count: { stations: 4, users: 1 }[q.name] ?? 0 }),
  })),
}));

import { describeUsage, projectUsage, PROJECT_LINKED_COLLECTIONS } from "./projectUsage";

describe("projectUsage", () => {
  it("minden kapcsolódó kollekciót megszámol", async () => {
    const usage = await projectUsage({}, "tapolca");
    expect(usage).toHaveLength(PROJECT_LINKED_COLLECTIONS.length);
    expect(usage.find((u) => u.collection === "stations").count).toBe(4);
  });

  it("csak a nem üres tételeket sorolja fel", async () => {
    const usage = await projectUsage({}, "tapolca");
    expect(describeUsage(usage)).toBe("4 állomás, 1 hozzárendelt admin");
  });

  it("üres használatra üres szöveg", () => {
    expect(describeUsage([{ label: "túra", count: 0 }])).toBe("");
  });
});
