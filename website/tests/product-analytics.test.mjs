import test from 'node:test';
import assert from 'node:assert/strict';
import { publicPath, entryName, EngagementClock, makeEvent } from '../lib/product-analytics.mjs';

test('only known public routes and named entry points can be sent', () => {
  assert.equal(publicPath('/admin'), null);
  assert.equal(publicPath('/auth/callback?token=private'), null);
  assert.equal(publicPath('/?secret=private'), '/');
  assert.equal(publicPath('/privacy'), '/privacy');
  assert.equal(entryName('hero_download'), 'hero_download');
  assert.equal(entryName('/Users/private/project'), null);
});
test('time excludes hidden periods, idle gaps and system sleep', () => {
  const clock = new EngagementClock();
  assert.equal(clock.sample(0, true, 0), 0);
  assert.equal(clock.sample(5000, true, 0), 5);
  assert.equal(clock.sample(10000, false, 0), 0);
  assert.equal(clock.sample(15000, true, 0), 0);
  assert.equal(clock.sample(20000, true, -60000), 0);
  assert.equal(clock.sample(3600000, true, 3600000), 0);
});
test('event is bounded and never copies URL queries or arbitrary properties', () => {
  const event = makeEvent('entry_click', 'browser-id', '/?secret=private', {entry:'hero_download', secret:'private'}, new Date('2026-09-23T01:00:00Z'), 'event-id');
  assert.equal(event.payload.properties.__path, '/');
  assert.equal(event.payload.properties.secret, undefined);
  assert.equal(event.payload.properties.__timestamp, '2026-09-23T01:00:00.000Z');
  assert.equal(event.payload.properties.event_id, 'event-id');
  assert.equal(makeEvent('private-text', 'id', '/'), null);
  assert.equal(makeEvent('screen_view', 'id', '/admin'), null);
});
