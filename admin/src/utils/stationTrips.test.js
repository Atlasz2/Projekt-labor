import { describe, expect, it } from "vitest";
import {
  stationTripIds,
  stationBelongsToTrip,
  stationOrderIndexForTrip,
  stationsForTrip,
  buildTripOrderOnSave,
  tripUnlinkPatch,
} from "./stationTrips";

describe("stationTripIds", () => {
  it("visszaadja az új tripIds tömböt, ha van", () => {
    expect(stationTripIds({ tripIds: ["t1", "t2"] })).toEqual(["t1", "t2"]);
  });

  it("kiszűri a duplikátumokat", () => {
    expect(stationTripIds({ tripIds: ["t1", "t1", "t2"] })).toEqual(["t1", "t2"]);
  });

  it("visszamenőleg a régi tripId mezőt egyelemű listaként adja", () => {
    expect(stationTripIds({ tripId: "t1" })).toEqual(["t1"]);
  });

  it("se tripIds, se tripId -> üres lista", () => {
    expect(stationTripIds({})).toEqual([]);
    expect(stationTripIds({ tripIds: [] })).toEqual([]);
  });
});

describe("stationBelongsToTrip", () => {
  it("egy állomás több túrának is megállója lehet", () => {
    const station = { tripIds: ["t1", "t2"] };
    expect(stationBelongsToTrip(station, "t1")).toBe(true);
    expect(stationBelongsToTrip(station, "t2")).toBe(true);
    expect(stationBelongsToTrip(station, "t3")).toBe(false);
  });
});

describe("stationOrderIndexForTrip", () => {
  it("a tripOrder map-ből olvas túránként külön sorrendet", () => {
    const station = { tripIds: ["t1", "t2"], tripOrder: { t1: 0, t2: 3 } };
    expect(stationOrderIndexForTrip(station, "t1")).toBe(0);
    expect(stationOrderIndexForTrip(station, "t2")).toBe(3);
  });

  it("régi egyetlen orderIndex mezőre visszamenőleg kompatibilis", () => {
    expect(stationOrderIndexForTrip({ tripId: "t1", orderIndex: 2 }, "t1")).toBe(2);
  });
});

describe("stationsForTrip", () => {
  it("egy állomás két túra listájában is szerepelhet, egymástól független sorrenddel", () => {
    const shared = { id: "shared", tripIds: ["a", "b"], tripOrder: { a: 0, b: 2 } };
    const stations = [
      shared,
      { id: "a2", tripIds: ["a"], tripOrder: { a: 1 } },
      { id: "b1", tripIds: ["b"], tripOrder: { b: 0 } },
      { id: "b2", tripIds: ["b"], tripOrder: { b: 1 } },
    ];
    expect(stationsForTrip(stations, "a").map((s) => s.id)).toEqual(["shared", "a2"]);
    expect(stationsForTrip(stations, "b").map((s) => s.id)).toEqual(["b1", "b2", "shared"]);
  });
});

describe("buildTripOrderOnSave", () => {
  it("új tagságot a túra végére fűz", () => {
    const allStations = [
      { id: "s1", tripIds: ["t1"], tripOrder: { t1: 0 } },
      { id: "s2", tripIds: ["t1"], tripOrder: { t1: 1 } },
    ];
    const result = buildTripOrderOnSave({
      station: null,
      allStations,
      selectedTripIds: ["t1"],
    });
    expect(result).toEqual({ t1: 2 });
  });

  it("meglévő tagság sorrendjét megtartja", () => {
    const station = { id: "s1", tripIds: ["t1"], tripOrder: { t1: 5 } };
    const result = buildTripOrderOnSave({
      station,
      allStations: [station],
      selectedTripIds: ["t1"],
    });
    expect(result).toEqual({ t1: 5 });
  });

  it("két túrát választva mindkettőhöz számol sorrendet", () => {
    const allStations = [
      { id: "s1", tripIds: ["t1"], tripOrder: { t1: 0 } },
      { id: "s2", tripIds: ["t2"], tripOrder: { t2: 0 } },
    ];
    const result = buildTripOrderOnSave({
      station: null,
      allStations,
      selectedTripIds: ["t1", "t2"],
    });
    expect(result).toEqual({ t1: 1, t2: 1 });
  });
});

describe("tripUnlinkPatch", () => {
  const ops = {
    arrayRemove: (v) => ({ op: "arrayRemove", v }),
    deleteField: () => ({ op: "delete" }),
  };

  it("kiveszi a túrát a tripIds tömbből és a tripOrder leképezésből", () => {
    const station = { tripIds: ["t1", "t2"], tripOrder: { t1: 0, t2: 3 } };
    expect(tripUnlinkPatch(station, "t2", ops)).toEqual({
      tripIds: { op: "arrayRemove", v: "t2" },
      "tripOrder.t2": { op: "delete" },
    });
  });

  it("a régi egyszeres tripId/orderIndex mezőket is törli", () => {
    expect(tripUnlinkPatch({ tripId: "t1", orderIndex: 2 }, "t1", ops)).toEqual({
      tripId: { op: "delete" },
      orderIndex: { op: "delete" },
    });
  });

  it("más túrához tartozó állomásnál nincs teendő", () => {
    expect(tripUnlinkPatch({ tripIds: ["t1"], tripOrder: { t1: 0 } }, "t9", ops)).toBeNull();
    expect(tripUnlinkPatch({}, "t1", ops)).toBeNull();
  });
});
