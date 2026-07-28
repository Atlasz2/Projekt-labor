// Viselkedési analitika – tiszta (I/O nélküli) aggregáció, hogy egységteszttel
// fedhető legyen. A Cloud Function (tripAnalytics) csak beolvassa a
// dokumentumokat és átadja ezeknek a függvényeknek.
//
// A jelenlegi adatmodellben a teljesítések a user_progress dokumentum
// tömbjeiben vannak (completedStations, completedEvents, completedTripIds),
// egyedi időbélyeg nélkül – ezért idő-alapú metrika (pl. átlagos befejezési
// idő) nem számolható, viszont a részvételi tölcsér és az állomás-népszerűség
// pontosan igen.

/**
 * @param {object} args
 * @param {Array<{id:string,name?:string,isActive?:boolean}>} args.trips
 * @param {Array<{id:string,name?:string,tripId?:string}>} args.stations
 * @param {Array<{completedStations?:string[],completedEvents?:string[],completedTripIds?:string[]}>} args.progressDocs
 * @returns {object} aggregált analitika (totals, trips, stations)
 */
export function computeTripAnalytics({
  trips = [],
  stations = [],
  progressDocs = [],
} = {}) {
  // Minden felhasználó teljesített állomásait halmazként tartjuk – gyors tagvizsgálat.
  const users = progressDocs.map((p) => ({
    stations: new Set((p?.completedStations ?? []).map(String)),
    tripIds: new Set((p?.completedTripIds ?? []).map(String)),
  }));

  // Állomásonként: hány felhasználó teljesítette.
  const stationCompletions = new Map();
  for (const u of users) {
    for (const sid of u.stations) {
      stationCompletions.set(sid, (stationCompletions.get(sid) ?? 0) + 1);
    }
  }

  const tripById = new Map(trips.map((t) => [String(t.id), t]));

  // Túránként a hozzá tartozó állomás-azonosítók.
  const tripStationIds = new Map();
  for (const s of stations) {
    const tid = s?.tripId != null ? String(s.tripId) : null;
    if (!tid) continue;
    if (!tripStationIds.has(tid)) tripStationIds.set(tid, []);
    tripStationIds.get(tid).push(String(s.id));
  }

  const tripStats = trips
    .map((t) => {
      const tid = String(t.id);
      const sids = tripStationIds.get(tid) ?? [];
      const stationCount = sids.length;

      let participants = 0; // legalább 1 állomást teljesített a túrából
      let finishers = 0; // az összes állomást teljesítette (vagy jelölt trip)
      let totalCompletedInTrip = 0;

      for (const u of users) {
        let done = 0;
        for (const sid of sids) if (u.stations.has(sid)) done += 1;
        if (done === 0) continue;
        participants += 1;
        totalCompletedInTrip += done;
        const finishedAll = stationCount > 0 && done === stationCount;
        if (finishedAll || u.tripIds.has(tid)) finishers += 1;
      }

      return {
        id: tid,
        name: String(t.name ?? 'Túra'),
        stationCount,
        participants,
        finishers,
        // Tölcsér: résztvevők -> befejezők. finishers ≤ participants garantált.
        completionRate: participants > 0 ? finishers / participants : 0,
        avgStationsPerParticipant:
          participants > 0 ? totalCompletedInTrip / participants : 0,
      };
    })
    .sort((a, b) => b.participants - a.participants || b.finishers - a.finishers);

  const stationStats = stations
    .map((s) => {
      const sid = String(s.id);
      const tid = s?.tripId != null ? String(s.tripId) : null;
      const trip = tid != null ? tripById.get(tid) : null;
      return {
        id: sid,
        name: String(s.name ?? 'Állomás'),
        tripId: tid,
        tripName: trip ? String(trip.name ?? '') : '',
        completions: stationCompletions.get(sid) ?? 0,
      };
    })
    .sort((a, b) => b.completions - a.completions || a.name.localeCompare(b.name, 'hu'));

  const participantsTotal = users.filter((u) => u.stations.size > 0).length;
  const totalStationCompletions = [...stationCompletions.values()].reduce(
    (a, b) => a + b,
    0,
  );

  return {
    totals: {
      participants: participantsTotal,
      totalStationCompletions,
      trips: trips.length,
      stations: stations.length,
      trackedUsers: users.length,
    },
    trips: tripStats,
    stations: stationStats,
  };
}
