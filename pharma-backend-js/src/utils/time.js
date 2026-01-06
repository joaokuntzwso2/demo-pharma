function nowIso() {
  return new Date().toISOString();
}

/**
 * URL-safe timestamp string for IDs:
 * 2026-01-06T09:07:57.118Z  ->  20260106T090757118Z
 */
function nowIdTs() {
  const d = new Date();
  const pad = (n, w = 2) => String(n).padStart(w, "0");

  const yyyy = d.getUTCFullYear();
  const mm = pad(d.getUTCMonth() + 1);
  const dd = pad(d.getUTCDate());
  const hh = pad(d.getUTCHours());
  const mi = pad(d.getUTCMinutes());
  const ss = pad(d.getUTCSeconds());
  const ms = pad(d.getUTCMilliseconds(), 3);

  return `${yyyy}${mm}${dd}T${hh}${mi}${ss}${ms}Z`;
}

function hoursDiff(fromIso) {
  const from = new Date(fromIso);
  const now = new Date();
  return (now - from) / (1000 * 60 * 60);
}

module.exports = { nowIso, nowIdTs, hoursDiff };
