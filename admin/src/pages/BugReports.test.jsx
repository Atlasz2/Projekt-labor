import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import BugReports from "./BugReports";

vi.mock("../firebaseConfig", () => ({ db: {} }));

vi.mock("firebase/firestore", () => ({
  collection: vi.fn(),
  getDocs: vi.fn(),
  updateDoc: vi.fn().mockResolvedValue(undefined),
  deleteDoc: vi.fn().mockResolvedValue(undefined),
  doc: vi.fn((_db, _col, id) => ({ _id: id })),
}));

import { getDocs, updateDoc, deleteDoc } from "firebase/firestore";

const makeReport = (overrides = {}) => ({
  id: "r1",
  title: "Teszt hiba",
  status: "open",
  description: "Leírás",
  created_at: null,
  admin_response: "",
  reported_by: { name: "Teszt User", email: "t@t.com" },
  ...overrides,
});

const makeSnap = (reports) => ({
  docs: reports.map((r) => ({ id: r.id, data: () => r })),
  size: reports.length,
});

describe("BugReports", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
  });

  it("shows loading StateCard initially", () => {
    getDocs.mockResolvedValue(makeSnap([]));
    render(<BugReports />);
    expect(screen.getByText("Hibajelentések betöltése...")).toBeInTheDocument();
  });

  it("shows empty StateCard when no reports", async () => {
    getDocs.mockResolvedValue(makeSnap([]));
    render(<BugReports />);
    await waitFor(() => expect(screen.getByText("Nincs hibajelentés")).toBeInTheDocument());
  });

  it("shows report title after load", async () => {
    getDocs.mockResolvedValue(makeSnap([makeReport()]));
    render(<BugReports />);
    await waitFor(() => expect(screen.getByText("Teszt hiba")).toBeInTheDocument());
  });

  it("shows multiple reports", async () => {
    getDocs.mockResolvedValue(
      makeSnap([makeReport({ id: "r1", title: "Hiba 1" }), makeReport({ id: "r2", title: "Hiba 2" })])
    );
    render(<BugReports />);
    await waitFor(() => {
      expect(screen.getByText("Hiba 1")).toBeInTheDocument();
      expect(screen.getByText("Hiba 2")).toBeInTheDocument();
    });
  });

  it("filter nyitott hides closed reports", async () => {
    getDocs.mockResolvedValue(
      makeSnap([
        makeReport({ id: "r1", title: "Nyitott hiba", status: "open" }),
        makeReport({ id: "r2", title: "Lezárt hiba", status: "closed" }),
      ])
    );
    render(<BugReports />);
    await waitFor(() => expect(screen.getByText("Nyitott hiba")).toBeInTheDocument());
    const select = screen.getByRole("combobox");
    await userEvent.click(select);
    await userEvent.click(screen.getByRole("option", { name: /Nyitott/ }));
    expect(screen.getByText("Nyitott hiba")).toBeInTheDocument();
    expect(screen.queryByText("Lezárt hiba")).not.toBeInTheDocument();
  });

  it("delete flow shows confirm dialog then success snackbar", async () => {
    getDocs.mockResolvedValue(makeSnap([makeReport()]));
    render(<BugReports />);
    await waitFor(() => expect(screen.getByText("Teszt hiba")).toBeInTheDocument());
    await userEvent.click(screen.getByText("Törlés"));
    expect(screen.getByText("Hibajelentés törlése")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Törlés" }));
    await waitFor(() => expect(screen.getByText("Hibajelentés törölve.")).toBeInTheDocument());
    expect(deleteDoc).toHaveBeenCalledOnce();
  });

  it("cancel in confirm dialog keeps the report", async () => {
    getDocs.mockResolvedValue(makeSnap([makeReport()]));
    render(<BugReports />);
    await waitFor(() => expect(screen.getByText("Teszt hiba")).toBeInTheDocument());
    await userEvent.click(screen.getByText("Törlés"));
    await userEvent.click(screen.getByText("Mégse"));
    expect(screen.getByText("Teszt hiba")).toBeInTheDocument();
    expect(deleteDoc).not.toHaveBeenCalled();
  });

  it("toggle status shows Hibajelentés lezárva snackbar for open report", async () => {
    getDocs.mockResolvedValue(makeSnap([makeReport({ status: "open" })]));
    render(<BugReports />);
    await waitFor(() => expect(screen.getByText("Lezárás")).toBeInTheDocument());
    await userEvent.click(screen.getByText("Lezárás"));
    await waitFor(() => expect(screen.getByText("Hibajelentés lezárva.")).toBeInTheDocument());
    expect(updateDoc).toHaveBeenCalledOnce();
  });

  it("toggle status shows Hibajelentés újranyitva snackbar for closed report", async () => {
    getDocs.mockResolvedValue(makeSnap([makeReport({ status: "closed" })]));
    render(<BugReports />);
    await waitFor(() => expect(screen.getByText("Újranyitás")).toBeInTheDocument());
    await userEvent.click(screen.getByText("Újranyitás"));
    await waitFor(() => expect(screen.getByText("Hibajelentés újranyitva.")).toBeInTheDocument());
  });

  it("save response shows Válasz mentve snackbar", async () => {
    getDocs.mockResolvedValue(makeSnap([makeReport()]));
    render(<BugReports />);
    await waitFor(() => expect(screen.getByPlaceholderText("Válasz a felhasználónak...")).toBeInTheDocument());
    await userEvent.type(screen.getByPlaceholderText("Válasz a felhasználónak..."), "Köszönjük a jelzést!");
    await userEvent.click(screen.getByText("Válasz mentése"));
    await waitFor(() => expect(screen.getByText("Válasz mentve.")).toBeInTheDocument());
    expect(updateDoc).toHaveBeenCalledOnce();
  });
});

