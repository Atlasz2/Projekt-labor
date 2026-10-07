import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("../firebaseConfig", () => ({ db: {}, auth: { name: "auth" }, functions: {} }));
vi.mock("../styles/Users.css", () => ({}));
vi.mock("../context/ProjectContext", () => ({
  useProject: () => ({
    activeProjectId: "nagyvazsony",
    activeProject: { id: "nagyvazsony", name: "Nagyvázsony" },
    canSwitchProject: true,
    projects: [{ id: "nagyvazsony", name: "Nagyvázsony" }],
  }),
}));
vi.mock("../context/AdminAuthContext", () => ({
  useAdminAuth: () => ({ userEmail: "dev@test.hu", userRole: "developer", userUid: "dev" }),
}));
vi.mock("firebase/firestore", () => ({
  collection: vi.fn((_db, ...parts) => parts.join("/")),
  getDocs: vi.fn(async (col) =>
    col === "users"
      ? { docs: [{ id: "u1", data: () => ({ email: "a@b.hu", role: "user", name: "Anna" }) }], size: 1 }
      : { docs: [], size: 0 },
  ),
  doc: vi.fn((_db, ...parts) => ({ _path: parts.join("/") })),
  setDoc: vi.fn(),
  serverTimestamp: vi.fn(),
  deleteField: vi.fn(),
}));
const invite = vi.fn();
vi.mock("firebase/functions", () => ({ httpsCallable: vi.fn(() => invite) }));
vi.mock("firebase/auth", () => ({ sendPasswordResetEmail: vi.fn() }));

import { sendPasswordResetEmail } from "firebase/auth";
import Users from "./Users";

async function submitInvite(email) {
  render(<Users />);
  await userEvent.click(await screen.findByRole("button", { name: /Admin meghívása/ }));
  await userEvent.type(screen.getByPlaceholderText("pl. admin@mencshely.hu"), email);
  await userEvent.click(screen.getByRole("button", { name: "Meghívás" }));
}

describe("Admin meghívása", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    invite.mockResolvedValue({ data: { ok: true, created: true, resetLink: "https://reset.example/link" } });
  });

  it("a meghívás után e-mailben elküldi a jelszó-beállító levelet", async () => {
    sendPasswordResetEmail.mockResolvedValue(undefined);
    await submitInvite("uj.admin@example.com");

    await waitFor(() =>
      expect(sendPasswordResetEmail).toHaveBeenCalledWith({ name: "auth", languageCode: "hu" }, "uj.admin@example.com"),
    );
    expect(await screen.findByText(/Meghívó elküldve: uj.admin@example.com/)).toBeInTheDocument();
  });

  it("ha az e-mail nem megy ki, a linket tartalékként megmutatja", async () => {
    sendPasswordResetEmail.mockRejectedValue(new Error("quota"));
    await submitInvite("uj.admin@example.com");

    expect((await screen.findAllByText(/nem sikerült elküldeni/)).length).toBeGreaterThan(0);
    expect(screen.getByDisplayValue("https://reset.example/link")).toBeInTheDocument();
  });
});
