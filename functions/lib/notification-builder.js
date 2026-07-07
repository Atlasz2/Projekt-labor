// Push-üzenet összeállítása egy új esemény dokumentumból. Tiszta függvény
// (nincs FCM-import), hogy unit-tesztelhető legyen; a küldést az index.js
// triggere végzi a getMessaging().send() hívással.

const TOPIC = 'events';

/** Rövidítés hosszú szöveghez, szóhatáron, ellipszissel. */
function truncate(text, max) {
  const clean = String(text ?? '').replace(/\s+/g, ' ').trim();
  if (clean.length <= max) return clean;
  const cut = clean.slice(0, max);
  const lastSpace = cut.lastIndexOf(' ');
  return `${(lastSpace > max * 0.6 ? cut.slice(0, lastSpace) : cut).trimEnd()}…`;
}

/**
 * FCM topic-üzenet egy eseményhez. `null`-t ad vissza, ha az esemény nem
 * értesítésre való (nincs neve), így a trigger csendben kihagyhatja.
 *
 * @param {{id: string, data: object}} event
 * @returns {object|null} getMessaging().send() bemenet, vagy null
 */
export function buildEventNotification(event) {
  const data = event?.data ?? {};
  const name = String(data.name ?? '').trim();
  if (!name) return null;

  const bodyParts = [];
  if (data.date) bodyParts.push(String(data.date).trim());
  if (data.location) bodyParts.push(String(data.location).trim());
  const contextLine = bodyParts.join(' • ');
  const description = truncate(data.description, 120);
  const body = [contextLine, description].filter(Boolean).join('\n');

  return {
    topic: TOPIC,
    notification: {
      title: `Új esemény: ${truncate(name, 60)}`,
      body: body || 'Nézd meg az új nagyvázsonyi eseményt az appban!',
    },
    data: {
      type: 'event',
      eventId: String(event.id ?? ''),
    },
    android: {
      priority: 'high',
      notification: { channelId: 'events', sound: 'default' },
    },
    apns: {
      payload: { aps: { sound: 'default' } },
    },
  };
}

export const EVENTS_TOPIC = TOPIC;
