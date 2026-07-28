import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import Analytics from "./Analytics";

vi.mock("../firebaseConfig", () => ({ functions: {} }));
vi.mock("../styles/Analytics.css", () => ({}));
vi.mock("firebase/functions", () => ({ httpsCallable: vi.fn() }));

import { httpsCallable } from "firebase/functions";

const PAYLOAD = {
  generatedAt: "2026-07-28T10:00:00.000Z",
  totals: { participants: 3, totalStationCompletions: 7, trips: 2, stations: 3, trackedUsers: 5 },
  trips: [
    { id: "t1", name: "Vár túra", stationCount: 2, participants: 3, finishers: 1, completionRate: 0.3333, avgStationsPerParticipant: 1.5 },
  ],
  stations: [
    { id: "s1", name: "Vár", tripId: "t1", tripName: "Vár túra", completions: 3 },
    { id: "s2", name: "Kápolna", tripId: "t1", tripName: "Vár túra", completions: 0 },
  ],
};

const mockCallable = (impl) => {
  httpsCallable.mockReturnValue(impl);
};

describe("Analytics", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("shows totals, funnel and station popularity after load", async () => {
    mockCallable(() => Promise.resolve({ data: PAYLOAD }));
    render(<Analytics />);

    await waitFor(() => expect(screen.getByText("Viselkedési analitika")).toBeInTheDocument());

    // Totals
    expect(screen.getByText("7")).toBeInTheDocument();
    // Funnel trip
    expect(screen.getByText("Vár túra", { selector: ".funnel-name" })).toBeInTheDocument();
    expect(screen.getByText("33% befejezés")).toBeInTheDocument();
    // Popularity: completed station shown, zero-completion station filtered out
    expect(screen.getByText("Vár", { selector: ".popularity-name" })).toBeInTheDocument();
    expect(screen.queryByText("Kápolna")).not.toBeInTheDocument();
  });

  it("shows a deploy hint when the function is not deployed", async () => {
    const err = new Error("not found");
    err.code = "functions/not-found";
    mockCallable(() => Promise.reject(err));
    render(<Analytics />);

    await waitFor(() =>
      expect(screen.getByText(/nincs telepítve/)).toBeInTheDocument()
    );
    expect(screen.getByText("Újrapróbálás")).toBeInTheDocument();
  });

  it("retries loading when Újrapróbálás is clicked", async () => {
    const err = new Error("fail");
    err.code = "internal";
    httpsCallable
      .mockReturnValueOnce(() => Promise.reject(err))
      .mockReturnValueOnce(() => Promise.resolve({ data: PAYLOAD }));

    render(<Analytics />);
    await waitFor(() => expect(screen.getByText("Újrapróbálás")).toBeInTheDocument());
    await userEvent.click(screen.getByText("Újrapróbálás"));
    await waitFor(() => expect(screen.getByText("Viselkedési analitika")).toBeInTheDocument());
  });
});
