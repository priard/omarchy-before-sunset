// Pure transition function; delays are one-shot, never a periodic location poll.
function initial() {
  return { enabled: false, phase: "disabled", dirty: false, failures: 0, delay: 0 }
}
function transition(old, event) {
  var s = Object.assign({}, old)
  if (event === "disable") {
    s.enabled = false
    s.dirty = true
    if (s.phase !== "lookup") s.phase = "disabled"
    return s
  }
  if (event === "enable" || event === "request") {
    if (event === "enable") s.enabled = true
    if (!s.enabled) return s
    s.failures = 0
    if (s.phase === "lookup") s.dirty = true
    else if (s.phase !== "waiting") { s.phase = "waiting"; s.delay = 10000 }
    return s
  }
  if (event === "start" && s.enabled && s.phase === "waiting") {
    s.phase = "lookup"; s.dirty = false
    return s
  }
  if ((event === "success" || event === "failure") && s.phase === "lookup") {
    if (!s.enabled) s.phase = "disabled"
    else if (s.dirty) { s.phase = "waiting"; s.delay = 10000 }
    else if (event === "success") { s.phase = "idle"; s.failures = 0 }
    else {
      var delays = [30000, 120000, 600000]
      s.delay = delays[s.failures] || 0
      s.failures++
      s.phase = s.delay ? "waiting" : "exhausted"
    }
    s.dirty = false
  }
  return s
}
function coordinates(latitude, longitude) {
  return typeof latitude === "number" && isFinite(latitude) && latitude >= -90 && latitude <= 90
    && typeof longitude === "number" && isFinite(longitude) && longitude >= -180 && longitude <= 180
}
