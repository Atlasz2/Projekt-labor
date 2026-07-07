import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildEventNotification, EVENTS_TOPIC } from '../lib/notification-builder.js';

test('név nélküli eseményre null (a trigger kihagyja)', () => {
  assert.equal(buildEventNotification({ id: 'e1', data: {} }), null);
  assert.equal(buildEventNotification({ id: 'e1', data: { name: '  ' } }), null);
});

test('teljes esemény: cím, dátum+helyszín, leírás összeáll', () => {
  const msg = buildEventNotification({
    id: 'e1',
    data: {
      name: 'Várjátékok',
      date: '2026-08-20',
      location: 'Kinizsi vár',
      description: 'Középkori forgatag a vár tövében.',
    },
  });

  assert.equal(msg.topic, EVENTS_TOPIC);
  assert.equal(msg.notification.title, 'Új esemény: Várjátékok');
  assert.equal(msg.notification.body, '2026-08-20 • Kinizsi vár\nKözépkori forgatag a vár tövében.');
  assert.equal(msg.data.type, 'event');
  assert.equal(msg.data.eventId, 'e1');
  assert.equal(msg.android.notification.channelId, 'events');
});

test('leírás nélkül csak a kontextussor kerül a törzsbe', () => {
  const msg = buildEventNotification({
    id: 'e2',
    data: { name: 'Koncert', date: '2026-09-01' },
  });
  assert.equal(msg.notification.body, '2026-09-01');
});

test('semmi extra mezőnél alapértelmezett törzs', () => {
  const msg = buildEventNotification({ id: 'e3', data: { name: 'Titkos program' } });
  assert.equal(msg.notification.body, 'Nézd meg az új nagyvázsonyi eseményt az appban!');
});

test('hosszú név és leírás szóhatáron rövidül, ellipszissel', () => {
  const longName = 'Nagyvázsonyi ' + 'történelmi '.repeat(10) + 'fesztivál';
  const longDesc = 'szó '.repeat(80);
  const msg = buildEventNotification({
    id: 'e4',
    data: { name: longName, description: longDesc },
  });

  assert.ok(msg.notification.title.length <= 'Új esemény: '.length + 61);
  assert.ok(msg.notification.title.endsWith('…'));
  // A leírás a 120 karakteres limit + ellipszis körül marad.
  assert.ok(msg.notification.body.length <= 121);
  assert.ok(msg.notification.body.endsWith('…'));
});

test('a whitespace-t normalizálja a törzsben', () => {
  const msg = buildEventNotification({
    id: 'e5',
    data: { name: 'X', description: 'sok    szóköz\n\nés   újsor' },
  });
  assert.equal(msg.notification.body, 'sok szóköz és újsor');
});
