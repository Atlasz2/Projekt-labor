import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const ctx = {
  projects: [
    { id: "nagyvazsony", name: "Nagyvázsony" },
    { id: "tapolca", name: "Tapolca" },
  ],
  activeProjectId: "nagyvazsony",
  activeProject: { id: "nagyvazsony", name: "Nagyvázsony" },
  loading: false,
  setActiveProjectId: vi.fn(),
  createProject: vi.fn(),
  renameProject: vi.fn(async () => {}),
  deleteProject: vi.fn(async () => {}),
};
vi.mock("../context/ProjectContext", () => ({ useProject: () => ctx }));

import Developer from "./Developer";

describe("Developer – települések kezelése", () => {
  beforeEach(() => vi.clearAllMocks());

  it("minden településnek van Átnevezés gombja, Törlés csak a nem alapértelmezettnek", () => {
    render(<Developer />);
    expect(screen.getAllByRole("button", { name: "Átnevezés" })).toHaveLength(2);
    expect(screen.getAllByRole("button", { name: "Törlés" })).toHaveLength(1);
  });

  it("átnevezéskor az új nevet menti", async () => {
    render(<Developer />);
    fireEvent.click(screen.getAllByRole("button", { name: "Átnevezés" })[1]);
    const input = screen.getByLabelText("Tapolca új neve");
    fireEvent.change(input, { target: { value: "Tapolca város" } });
    fireEvent.click(screen.getByRole("button", { name: "Mentés" }));
    await waitFor(() => expect(ctx.renameProject).toHaveBeenCalledWith("tapolca", "Tapolca város"));
  });

  it("a Mégse kilép a szerkesztésből mentés nélkül", () => {
    render(<Developer />);
    fireEvent.click(screen.getAllByRole("button", { name: "Átnevezés" })[1]);
    fireEvent.click(screen.getByRole("button", { name: "Mégse" }));
    expect(screen.queryByLabelText("Tapolca új neve")).toBeNull();
    expect(ctx.renameProject).not.toHaveBeenCalled();
  });

  it("törlés megerősítés után; a tiltott törlés oka megjelenik", async () => {
    ctx.deleteProject.mockRejectedValueOnce(new Error("A település nem törölhető, mert még hozzá tartozik: 3 túra."));
    render(<Developer />);
    fireEvent.click(screen.getByRole("button", { name: "Törlés" }));
    const dialogButtons = await screen.findAllByRole("button", { name: "Törlés" });
    fireEvent.click(dialogButtons[dialogButtons.length - 1]);
    await waitFor(() => expect(ctx.deleteProject).toHaveBeenCalledWith("tapolca"));
    expect(await screen.findByText(/3 túra/)).toBeInTheDocument();
  });
});
