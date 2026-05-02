import { act, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AdminAuthProvider, useAdminAuth } from "./AdminAuthContext";

// ── Firebase Auth mock ──────────────────────────────────────────────────────
let capturedAuthCallback;
const mockSignOut = vi.fn().mockResolvedValue(undefined);

vi.mock("firebase/auth", () => ({
  onAuthStateChanged: vi.fn((_auth, cb) => {
    capturedAuthCallback = cb;
    return vi.fn(); // unsubscribe
  }),
  signOut: (...args) => mockSignOut(...args),
}));

vi.mock("../firebaseConfig", () => ({ auth: {}, db: {} }));

// ── resolveUserRole mock ────────────────────────────────────────────────────
const mockResolveUserRole = vi.fn();
vi.mock("../utils/resolveUserRole", () => ({
  resolveUserRole: (...args) => mockResolveUserRole(...args),
}));

// ── Helper consumer component ───────────────────────────────────────────────
function AuthConsumer() {
  const { isLoggedIn, userRole, userEmail, loading } = useAdminAuth();
  return (
    <div>
      <span data-testid="loading">{String(loading)}</span>
      <span data-testid="isLoggedIn">{String(isLoggedIn)}</span>
      <span data-testid="userRole">{userRole}</span>
      <span data-testid="userEmail">{userEmail}</span>
    </div>
  );
}

function renderProvider() {
  return render(
    <AdminAuthProvider>
      <AuthConsumer />
    </AdminAuthProvider>
  );
}

describe("AdminAuthContext", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    capturedAuthCallback = undefined;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it("starts in loading state", () => {
    renderProvider();
    expect(screen.getByTestId("loading").textContent).toBe("true");
    expect(screen.getByTestId("isLoggedIn").textContent).toBe("false");
  });

  it("sets loading=false and isLoggedIn=false when no user is signed in", async () => {
    renderProvider();
    await act(async () => {
      capturedAuthCallback(null);
    });
    expect(screen.getByTestId("loading").textContent).toBe("false");
    expect(screen.getByTestId("isLoggedIn").textContent).toBe("false");
  });

  it("sets isLoggedIn=true and exposes role/email for admin user", async () => {
    mockResolveUserRole.mockResolvedValueOnce("admin");
    renderProvider();
    await act(async () => {
      capturedAuthCallback({ uid: "u1", email: "admin@test.com" });
    });
    expect(screen.getByTestId("loading").textContent).toBe("false");
    expect(screen.getByTestId("isLoggedIn").textContent).toBe("true");
    expect(screen.getByTestId("userRole").textContent).toBe("admin");
    expect(screen.getByTestId("userEmail").textContent).toBe("admin@test.com");
  });

  it("signs out and leaves isLoggedIn=false for a non-admin user", async () => {
    mockResolveUserRole.mockResolvedValueOnce("user");
    renderProvider();
    await act(async () => {
      capturedAuthCallback({ uid: "u2", email: "regular@test.com" });
    });
    expect(mockSignOut).toHaveBeenCalledOnce();
    expect(screen.getByTestId("isLoggedIn").textContent).toBe("false");
    expect(screen.getByTestId("loading").textContent).toBe("false");
  });

  it("throws when useAdminAuth is used outside of AdminAuthProvider", () => {
    // Suppress React error boundary noise in test output
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => {});
    expect(() => render(<AuthConsumer />)).toThrow(
      "useAdminAuth must be used within AdminAuthProvider"
    );
    consoleError.mockRestore();
  });
});
