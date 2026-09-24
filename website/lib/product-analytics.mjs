const paths = new Set(['/', '/privacy', '/rankings']);
const entries = new Set(['nav_download','hero_download','install_download','footer_download','nav_features','nav_rankings','nav_source','nav_privacy','explore_details','explore_rankings','privacy_details','footer_source','footer_rankings','footer_privacy','back_top']);
export function publicPath(value) {
  const path = value.split(/[?#]/, 1)[0];
  return paths.has(path) ? path : null;
}
export function entryName(value) { return entries.has(value) ? value : null; }
export class EngagementClock {
  last = null;
  wasVisible = false;
  sample(now, visible, lastInput) {
    const previous = this.last;
    const wasVisible = this.wasVisible;
    this.last = now;
    this.wasVisible = visible;
    if (previous === null || now < previous || now - previous > 15000 || !wasVisible || !visible || now - lastInput >= 60000) return 0;
    return (now - previous) / 1000;
  }
}
export function makeEvent(name, profileId, path, values = {}, now = new Date(), id = crypto.randomUUID()) {
  const route = publicPath(path);
  if (!route || !['screen_view','entry_click','website_engagement'].includes(name)) return null;
  const properties = {product:'tokenmini', platform:'web', __path:route, __timestamp:now.toISOString(), event_id:id};
  if (name === 'entry_click') {
    const entry = entryName(values.entry);
    if (!entry) return null;
    properties.entry = entry;
  }
  if (name === 'website_engagement') properties.interaction_seconds = Math.min(300, Math.max(0, Number(values.seconds) || 0));
  return {type:'track', payload:{name, profileId, properties}};
}
