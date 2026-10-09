import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("../firebaseConfig", () => ({ auth: { name: "auth" } }));
vi.mock("../styles/Login.css", () => ({}));
vi.mock("../utils/resolveUserRole", () => ({ resolveUserRole: vi.fn() }));
vi.mock("firebase/auth", () => ({
  browserLocalPersistence: {},
  sendPasswordResetEmail: vi.fn(),
  setPersistence: vi.fn(),
  signInWithEmailAndPassword: vi.fn(),
  signOut: vi.fn(),
}));

import { sendPasswordResetEmail } from "firebase/auth";
import Login, { RESET_SENT_MESSAGE } from "./Login";

async function openReset() {
  render(<Login />);
  await userEvent.click(screen.getByRole("button", { name: "Elfelejtettem a jelszavam" }));
  expect(screen.getByRole("heading", { name: "Elfelejtett jelszó" })).toBeInTheDocument();
}

describe("Elfelejtett jelszó", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
  });

  it("magyar nyelvű visszaállító levelet küld, visszatérő linkkel", async () => {
    sendPasswordResetEmail.mockResolvedValue(undefined);
    await openReset();
    await userEvent.type(screen.getByLabelText("Email cím"), "Admin@Example.com ");
    await userEvent.click(screen.getByRole("button", { name: "Visszaállító link küldése" }));

    await waitFor(() => expect(screen.getByText(RESET_SENT_MESSAGE)).toBeInTheDocument());
    expect(sendPasswordResetEmail).toHaveBeenCalledWith(
      expect.objectContaining({ languageCode: "hu" }),
      "admin@example.com",
      { url: `${window.location.origin}/` },
    );
  });

  it("nem létező fióknál is ugyanazt mondja (nem árulja el, ki admin)", async () => {
    sendPasswordResetEmail.mockRejectedValue({ code: "auth/user-not-found" });
    await openReset();
    await userEvent.type(screen.getByLabelText("Email cím"), "nincs@example.com");
    await userEvent.click(screen.getByRole("button", { name: "Visszaállító link küldése" }));
    expect(await screen.findByText(RESET_SENT_MESSAGE)).toBeInTheDocument();
  });

  it("ha a domain nincs engedélyezve, visszatérő link nélkül küldi", async () => {
    sendPasswordResetEmail
      .mockRejectedValueOnce({ code: "auth/unauthorized-continue-uri" })
      .mockResolvedValueOnce(undefined);
    await openReset();
    await userEvent.type(screen.getByLabelText("Email cím"), "admin@example.com");
    await userEvent.click(screen.getByRole("button", { name: "Visszaállító link küldése" }));
    expect(await screen.findByText(RESET_SENT_MESSAGE)).toBeInTheDocument();
    expect(sendPasswordResetEmail).toHaveBeenLastCalledWith(
      expect.anything(),
      "admin@example.com",
    );
  });

  it("vissza lehet térni a belépéshez", async () => {
    await openReset();
    await userEvent.click(screen.getByRole("button", { name: /Vissza a belépéshez/ }));
    expect(screen.getByRole("heading", { name: "Admin belépés" })).toBeInTheDocument();
  });
});
