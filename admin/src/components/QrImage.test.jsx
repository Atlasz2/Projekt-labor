import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import QrImage from "./QrImage";

describe("QrImage", () => {
  it("a helyben generált QR-képet jeleníti meg", async () => {
    render(<QrImage value="VAR-001" alt="QR Kinizsi vár" size={120} />);
    const img = await screen.findByRole("img", { name: "QR Kinizsi vár" });
    expect(img.getAttribute("src")).toMatch(/^data:image\/png;base64,/);
    expect(img.getAttribute("width")).toBe("120");
  });
});
