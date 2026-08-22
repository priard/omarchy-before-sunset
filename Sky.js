// The sun and the moon, drawn in braille.
//
// A braille cell is a 2x4 grid of dots, so six characters across three lines
// give a canvas of twelve dots square — enough for a disc that reads as round
// rather than as a rectangle, which is more than a character-cell drawing with
// block elements can manage at this size.
//
// Pure: every function takes what it needs and returns an array of strings, one
// per line. Nothing here reads a clock or a setting.

// Dot values by column and row within the cell. The fourth row is the one the
// original six-dot braille did not have, which is why its two bits sit apart
// from the rest.
var DOTS = [
  [0x01, 0x02, 0x04, 0x40],
  [0x08, 0x10, 0x20, 0x80]
]

var SIZE = 12
var CENTRE = (SIZE - 1) / 2

function frame(lit) {
  var lines = []

  for (var cy = 0; cy < SIZE; cy += 4) {
    var line = ""
    for (var cx = 0; cx < SIZE; cx += 2) {
      var bits = 0
      for (var dx = 0; dx < 2; dx++)
        for (var dy = 0; dy < 4; dy++)
          if (lit(cx + dx, cy + dy)) bits |= DOTS[dx][dy]
      line += String.fromCharCode(0x2800 + bits)
    }
    lines.push(line)
  }

  return lines
}

var DISC = 3.4
var REACH = 5.6

// Eight rays, turned by `phase` radians. The disc itself never moves: what
// turns is the light coming off it.
function sun(phase) {
  return frame(function (x, y) {
    var dx = x - CENTRE
    var dy = y - CENTRE
    var distance = Math.sqrt(dx * dx + dy * dy)

    if (distance <= DISC) return true
    if (distance > REACH) return false

    return Math.cos((Math.atan2(dy, dx) + phase) * 4) > 0.55
  })
}

var MOON = 4.6

// The terminator is an ellipse across the disc, which is what makes a crescent
// a crescent rather than a bitten circle: its width is the cosine of how far
// through the month the moon has gone.
//
// The unlit part is drawn as a rim rather than as nothing, so a new moon is
// still visibly a moon and not an empty square.
function moon(illumination, waxing) {
  var lit = Math.max(0, Math.min(1, illumination))
  var edge = MOON * (1 - 2 * lit)

  return frame(function (x, y) {
    var dx = waxing ? x - CENTRE : CENTRE - x
    var dy = y - CENTRE
    var distance = Math.sqrt(dx * dx + dy * dy)

    if (distance > MOON + 0.5) return false
    if (distance > MOON - 0.9) return true

    return dx >= edge * Math.sqrt(Math.max(0, 1 - (dy / MOON) * (dy / MOON)))
  })
}
