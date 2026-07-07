import { describe, it, expect } from "vitest";
import { buildCsv } from "./exportCsv";

const columns = [
  { key: "name", label: "Név" },
  { key: "points", label: "Pont" },
];

describe("buildCsv", () => {
  it("writes a header row from the column labels", () => {
    const csv = buildCsv([], columns);
    expect(csv).toBe("Név,Pont");
  });

  it("renders rows with CRLF line endings", () => {
    const csv = buildCsv(
      [{ name: "Anna", points: 50 }, { name: "Béla", points: 80 }],
      columns
    );
    expect(csv).toBe("Név,Pont\r\nAnna,50\r\nBéla,80");
  });

  it("quotes cells containing commas, quotes, semicolons or newlines", () => {
    const csv = buildCsv(
      [{ name: 'Nagy, Anna', points: 'a"b' }, { name: "két\nsor", points: "x;y" }],
      columns
    );
    const lines = csv.split("\r\n");
    expect(lines[1]).toBe('"Nagy, Anna","a""b"');
    expect(lines[2]).toBe('"két\nsor","x;y"');
  });

  it("treats null and undefined as empty cells", () => {
    const csv = buildCsv([{ name: null, points: undefined }], columns);
    expect(csv.split("\r\n")[1]).toBe(",");
  });

  it("applies a column format function with access to the row", () => {
    const cols = [
      { key: "role", label: "Szerep", format: (v) => (v === "admin" ? "Admin" : "Felhasználó") },
      { key: "n", label: "Rang", format: (v, row) => `#${row.n}` },
    ];
    const csv = buildCsv([{ role: "admin", n: 1 }], cols);
    expect(csv.split("\r\n")[1]).toBe("Admin,#1");
  });
});
