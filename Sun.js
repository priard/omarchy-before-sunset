// Sunrise and sunset for a date and a place on earth.
//
// This is the almanac algorithm published by the US Naval Observatory (the one
// usually labelled "Sunrise/Sunset Algorithm"): closed form, no ephemeris
// table, no network call, accurate to about a minute. That is several orders
// of magnitude below the point at which anyone notices their desktop changing
// colour early or late.
//
// Everything here is pure and returns absolute instants (epoch milliseconds or
// Date objects), never wall-clock strings. Time zones and daylight saving are
// left entirely to the host Date implementation.

var DEGREES_PER_HOUR = 15
var MS_PER_DAY = 86400000
var MS_PER_HOUR = 3600000
var MS_PER_MINUTE = 60000

// The sun's centre sits 50 arcminutes below the horizon at the moment the disc
// appears to touch it, once refraction and the disc's own radius are counted.
var ZENITH_OFFICIAL = 90.8333333
var ZENITH_CIVIL = 96
var ZENITH_NAUTICAL = 102
var ZENITH_ASTRONOMICAL = 108

function toRadians(degrees) {
  return degrees * Math.PI / 180
}

function toDegrees(radians) {
  return radians * 180 / Math.PI
}

function normalizeDegrees(value) {
  var wrapped = value % 360
  return wrapped < 0 ? wrapped + 360 : wrapped
}

function normalizeHours(value) {
  var wrapped = value % 24
  return wrapped < 0 ? wrapped + 24 : wrapped
}

// Counted in UTC on purpose: subtracting two local midnights across a daylight
// saving boundary is off by an hour and can floor to the wrong day.
function dayOfYear(date) {
  var yearStart = Date.UTC(date.getFullYear(), 0, 1)
  var day = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate())
  return Math.round((day - yearStart) / MS_PER_DAY) + 1
}

// Zenith angle for a twilight name, a number, or anything unrecognised (which
// falls back to the visible horizon).
function zenithFor(twilight) {
  if (typeof twilight === "number" && !isNaN(twilight)) return twilight

  switch (String(twilight || "").toLowerCase()) {
  case "civil":
    return ZENITH_CIVIL
  case "nautical":
    return ZENITH_NAUTICAL
  case "astronomical":
    return ZENITH_ASTRONOMICAL
  default:
    return ZENITH_OFFICIAL
  }
}

// The instant the sun crosses `zenith` going up (rising) or down, on the local
// calendar day of `date`. Returns null inside the polar circles on days when
// the crossing never happens at all.
function sunEvent(date, latitude, longitude, rising, zenith) {
  var angle = zenith === undefined ? ZENITH_OFFICIAL : zenith
  var day = dayOfYear(date)
  var longitudeHour = longitude / DEGREES_PER_HOUR

  // Rough time of the event in days, used only to place the sun on its orbit.
  var approximate = day + (((rising ? 6 : 18) - longitudeHour) / 24)

  var meanAnomaly = (0.9856 * approximate) - 3.289
  var trueLongitude = normalizeDegrees(meanAnomaly
    + (1.916 * Math.sin(toRadians(meanAnomaly)))
    + (0.020 * Math.sin(toRadians(2 * meanAnomaly)))
    + 282.634)

  var rightAscension = normalizeDegrees(toDegrees(Math.atan(0.91764 * Math.tan(toRadians(trueLongitude)))))
  // atan() folds four quadrants onto two, so the right ascension has to be put
  // back into the quadrant the true longitude is actually in.
  var longitudeQuadrant = Math.floor(trueLongitude / 90) * 90
  var ascensionQuadrant = Math.floor(rightAscension / 90) * 90
  rightAscension = (rightAscension + (longitudeQuadrant - ascensionQuadrant)) / DEGREES_PER_HOUR

  var sinDeclination = 0.39782 * Math.sin(toRadians(trueLongitude))
  var cosDeclination = Math.cos(Math.asin(sinDeclination))

  var latitudeRadians = toRadians(latitude)
  var cosHourAngle = (Math.cos(toRadians(angle)) - (sinDeclination * Math.sin(latitudeRadians)))
    / (cosDeclination * Math.cos(latitudeRadians))

  // Polar day (sun never sets) or polar night (never rises): the horizon is
  // simply not crossed, and there is no event to report.
  if (cosHourAngle > 1 || cosHourAngle < -1) return null

  var hourAngle = toDegrees(Math.acos(cosHourAngle))
  if (rising) hourAngle = 360 - hourAngle
  hourAngle = hourAngle / DEGREES_PER_HOUR

  var localMeanTime = hourAngle + rightAscension - (0.06571 * approximate) - 6.622
  var universalTime = normalizeHours(localMeanTime - longitudeHour)

  // `universalTime` is a clock reading with the date wrapped off it. Anchor it
  // to whichever UTC day lands the event nearest local noon, so time zones far
  // from their nominal meridian cannot end up a day out.
  var localNoon = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12).getTime()
  var midnightUtc = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate())
  var best = null
  for (var offset = -1; offset <= 1; offset++) {
    var candidate = midnightUtc + (offset * MS_PER_DAY) + (universalTime * MS_PER_HOUR)
    if (best === null || Math.abs(candidate - localNoon) < Math.abs(best - localNoon)) best = candidate
  }

  return new Date(best)
}

function sunrise(date, latitude, longitude, zenith) {
  return sunEvent(date, latitude, longitude, true, zenith)
}

function sunset(date, latitude, longitude, zenith) {
  return sunEvent(date, latitude, longitude, false, zenith)
}

// "07:30" -> minutes since local midnight, or null when unparseable.
function parseClock(text) {
  var match = /^\s*([0-9]{1,2})\s*:\s*([0-9]{2})\s*$/.exec(String(text || ""))
  if (!match) return null

  var hours = parseInt(match[1], 10)
  var minutes = parseInt(match[2], 10)
  if (hours > 23 || minutes > 59) return null

  return (hours * 60) + minutes
}

// Given every transition in a window around now, work out which half of the
// day we are in and when it ends. Events must be sorted by time.
function scheduleFromEvents(now, events) {
  var moment = now.getTime()
  var current = null
  var next = null

  for (var i = 0; i < events.length; i++) {
    if (events[i].at <= moment) current = events[i]
    else {
      next = events[i]
      break
    }
  }

  if (current === null && next === null) return null

  // Before the earliest known event we are in the half of the day that the
  // upcoming event brings to an end.
  var mode = current ? current.mode : (next.mode === "day" ? "night" : "day")

  return {
    mode: mode,
    since: current ? current.at : null,
    next: next ? next.at : null
  }
}

// Which half of the day the sun says we are in, and when it flips.
// Returns "day" or "night" — never a colour, because a user may run a light
// theme on both sides.
//
// options: { twilight, sunriseOffsetMinutes, sunsetOffsetMinutes }
// Offsets are minutes relative to the event, negative meaning earlier, and let
// someone ask for "go dark twenty minutes before the sun actually goes".
function sunSchedule(now, latitude, longitude, options) {
  var opts = options || {}
  var zenith = zenithFor(opts.twilight)
  var sunriseShift = (Number(opts.sunriseOffsetMinutes) || 0) * MS_PER_MINUTE
  var sunsetShift = (Number(opts.sunsetOffsetMinutes) || 0) * MS_PER_MINUTE

  // Yesterday through tomorrow, so there is always a transition on both sides
  // of `now` no matter the hour or the offsets.
  var events = []
  for (var offset = -1; offset <= 1; offset++) {
    var day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset)
    var up = sunEvent(day, latitude, longitude, true, zenith)
    var down = sunEvent(day, latitude, longitude, false, zenith)
    if (up) events.push({ at: up.getTime() + sunriseShift, mode: "day" })
    if (down) events.push({ at: down.getTime() + sunsetShift, mode: "night" })
  }

  events.sort(function(a, b) { return a.at - b.at })

  return scheduleFromEvents(now, events)
}

// Same answer shape, driven by two clock times instead of the sun. Used when
// the user asks for fixed hours, and as the fallback during polar day or
// polar night when there is no sunrise or sunset to follow.
function fixedSchedule(now, dayAt, nightAt) {
  var dayMinutes = parseClock(dayAt)
  var nightMinutes = parseClock(nightAt)
  if (dayMinutes === null || nightMinutes === null) return null

  var events = []
  for (var offset = -1; offset <= 1; offset++) {
    var midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset).getTime()
    events.push({ at: midnight + (dayMinutes * MS_PER_MINUTE), mode: "day" })
    events.push({ at: midnight + (nightMinutes * MS_PER_MINUTE), mode: "night" })
  }

  events.sort(function(a, b) { return a.at - b.at })

  return scheduleFromEvents(now, events)
}

// ------------------------------------------------------------------- moon

// The moon's age and how much of its disc is lit, for the icon that stands in
// for night. Counted from a known new moon through the mean synodic month,
// which is a picture rather than an ephemeris: it drifts by a few hours against
// the real moon and by under a day across a century. Nobody looking at a
// twelve-dot icon can tell, and the alternative is a table this plugin has no
// business carrying.
var SYNODIC_MONTH = 29.530588853
var KNOWN_NEW_MOON = Date.UTC(2000, 0, 6, 18, 14)

function moonAge(when) {
  var days = ((when ? when.getTime() : Date.now()) - KNOWN_NEW_MOON) / MS_PER_DAY
  var age = days % SYNODIC_MONTH
  return age < 0 ? age + SYNODIC_MONTH : age
}

// 0 at new moon, 1 at full.
function moonIllumination(when) {
  return (1 - Math.cos(2 * Math.PI * moonAge(when) / SYNODIC_MONTH)) / 2
}

// Which limb is lit. Waxing lights the right in the northern hemisphere, and
// this draws it that way: the icon is a picture of the moon people grew up
// with, not a rendering of the sky above the coordinates in the settings.
function moonWaxing(when) {
  return moonAge(when) < SYNODIC_MONTH / 2
}
