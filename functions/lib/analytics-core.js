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
// Biztonságos tömbösítés: régi/kézzel szerkesztett dokumentumban a mező lehet
// hiányzó, null, vagy akár nem-tömb (pl. objektum) – ilyenkor üres tömböt adunk,
// hogy az aggregáció ne dobjon (különben a callable "internal" hibát adna).
const asStringArray = (v) => (Array.isArray(v) ? v.map(String) : []);

// A completedStationsAt map ({ stationId: epochMillis }) biztonságos beolvasása
// Map<stationId, ms> alakba. Csak véges számokat fogad el (a callable a
// Firestore Timestamp-eket előre millisec-re konvertálja).
const asTimestampMap = (v) => {
  const out = new Map();
  if (v && typeof v === 'object' && !Array.isArray(v)) {
    for (const [key, value] of Object.entries(v)) {
      const ms = Number(value);
      if (Number.isFinite(ms)) out.set(String(key), ms);
    }
  }
  return out;
};

export function computeTripAnalytics({
  trips = [],
  stations = [],
  progressDocs = [],
} = {}) {
  const tripsArr = Array.isArray(trips) ? trips : [];
  const stationsArr = Array.isArray(stations) ? stations : [];
  const progressArr = Array.isArray(progressDocs) ? progressDocs : [];

  // Minden felhasználó teljesített állomásait halmazként tartjuk – gyors tagvizsgálat.
  const users = progressArr.map((p) => ({
    stations: new Set(asStringArray(p?.completedStations)),
    tripIds: new Set(asStringArray(p?.completedTripIds)),
    stationsAt: asTimestampMap(p?.completedStationsAt),
  }));

  // Állomásonként: hány felhasználó teljesítette.
  const stationCompletions = new Map();
  for (const u of users) {
    for (const sid of u.stations) {
      stationCompletions.set(sid, (stationCompletions.get(sid) ?? 0) + 1);
    }
  }

  const tripById = new Map(tripsArr.map((t) => [String(t?.id), t]));

  // Túránként a hozzá tartozó állomás-azonosítók.
  const tripStationIds = new Map();
  for (const s of stationsArr) {
    const tid = s?.tripId != null ? String(s.tripId) : null;
    if (!tid) continue;
    if (!tripStationIds.has(tid)) tripStationIds.set(tid, []);
    tripStationIds.get(tid).push(String(s?.id));
  }

  const tripStats = tripsArr
    .map((t) => {
      const tid = String(t.id);
      const sids = tripStationIds.get(tid) ?? [];
      const stationCount = sids.length;

      let participants = 0; // legalább 1 állomást teljesített a túrából
      let finishers = 0; // az összes állomást teljesítette (vagy jelölt trip)
      let totalCompletedInTrip = 0;
      const completionDurationsMs = []; // befejezők első→utolsó állomás ideje

      for (const u of users) {
        let done = 0;
        for (const sid of sids) if (u.stations.has(sid)) done += 1;
        if (done === 0) continue;
        participants += 1;
        totalCompletedInTrip += done;
        const finishedAll = stationCount > 0 && done === stationCount;
        if (finishedAll || u.tripIds.has(tid)) finishers += 1;

        // Befejezési idő: csak akkor, ha minden állomáshoz van időbélyeg
        // (első→utolsó). A régi, időbélyeg nélküli teljesítések kimaradnak.
        if (finishedAll) {
          const times = [];
          for (const sid of sids) {
            const ts = u.stationsAt.get(sid);
            if (ts != null) times.push(ts);
          }
          if (times.length === stationCount) {
            completionDurationsMs.push(Math.max(...times) - Math.min(...times));
          }
        }
      }

      const avgCompletionMinutes =
        completionDurationsMs.length > 0
          ? Math.round(
              completionDurationsMs.reduce((a, b) => a + b, 0) /
                completionDurationsMs.length /
                60000,
            )
          : null;

      return {
        id: tid,
        name: String(t?.name ?? 'Túra'),
        stationCount,
        participants,
        finishers,
        // Tölcsér: résztvevők -> befejezők. finishers ≤ participants garantált.
        completionRate: participants > 0 ? finishers / participants : 0,
        avgStationsPerParticipant:
          participants > 0 ? totalCompletedInTrip / participants : 0,
        // Átlagos befejezési idő percben (null, ha még nincs időbélyeges adat).
        avgCompletionMinutes,
        completionTimeSamples: completionDurationsMs.length,
      };
    })
    .sort((a, b) => b.participants - a.participants || b.finishers - a.finishers);

  const stationStats = stationsArr
    .map((s) => {
      const sid = String(s?.id);
      const tid = s?.tripId != null ? String(s.tripId) : null;
      const trip = tid != null ? tripById.get(tid) : null;
      return {
        id: sid,
        name: String(s?.name ?? 'Állomás'),
        tripId: tid,
        tripName: trip ? String(trip?.name ?? '') : '',
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
      trips: tripsArr.length,
      stations: stationsArr.length,
      trackedUsers: users.length,
    },
    trips: tripStats,
    stations: stationStats,
  };
}
