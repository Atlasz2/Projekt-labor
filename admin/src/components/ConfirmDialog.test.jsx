import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import ConfirmDialog from "./ConfirmDialog";

describe("ConfirmDialog", () => {
  it("does not render when closed", () => {
    render(
      <ConfirmDialog
        open={false}
        onConfirm={vi.fn()}
        onClose={vi.fn()}
      />
    );
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("shows default title and message when open", () => {
    render(
      <ConfirmDialog
        open={true}
        onConfirm={vi.fn()}
        onClose={vi.fn()}
      />
    );
    expect(screen.getByText("Megerősítés")).toBeInTheDocument();
    expect(screen.getByText("Biztosan folytatod?")).toBeInTheDocument();
  });

  it("shows custom title, message and button labels", () => {
    render(
      <ConfirmDialog
        open={true}
        title="Törlés"
        message="Biztosan törölni?"
        confirmText="Igen, törlöm"
        cancelText="Mégse"
        onConfirm={vi.fn()}
        onClose={vi.fn()}
      />
    );
    expect(screen.getByText("Törlés")).toBeInTheDocument();
    expect(screen.getByText("Biztosan törölni?")).toBeInTheDocument();
    expect(screen.getByText("Igen, törlöm")).toBeInTheDocument();
    expect(screen.getByText("Mégse")).toBeInTheDocument();
  });

  it("calls onConfirm when confirm button is clicked", async () => {
    const onConfirm = vi.fn();
    render(
      <ConfirmDialog
        open={true}
        confirmText="Igen"
        onConfirm={onConfirm}
        onClose={vi.fn()}
      />
    );
    await userEvent.click(screen.getByText("Igen"));
    expect(onConfirm).toHaveBeenCalledOnce();
  });

  it("calls onClose when cancel button is clicked", async () => {
    const onClose = vi.fn();
    render(
      <ConfirmDialog
        open={true}
        cancelText="Mégse"
        onConfirm={vi.fn()}
        onClose={onClose}
      />
    );
    await userEvent.click(screen.getByText("Mégse"));
    expect(onClose).toHaveBeenCalledOnce();
  });
});
