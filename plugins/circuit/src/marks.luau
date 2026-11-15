--!strict
--[[
  What is drawn over a schematic to reason about it: current arrows and
  voltage polarities on parts, labels at points, current paths, mesh loops,
  crossed-out parts and highlighted regions. Marks are coloured so they stand
  apart from the circuit; the colours are mid-tones that read on a light and
  on a dark page.
]]
local canvas = require("./canvas")
local symbols = require("./symbols")

type Canvas = canvas.Canvas
type Placement = symbols.Placement

-- Which ways a point is already taken by a wire, a part or a symbol.
-- `stack` counts the labels already piled above it.
export type Sides = { up: boolean?, down: boolean?, left: boolean?, right: boolean?, stack: number? }

local COLORS: { [string]: string } = {
  red = "#e03131",
  blue = "#1c7ed6",
  green = "#2f9e44",
  orange = "#e8590c",
  purple = "#7048e8",
  gray = "#868e96",
}

local marks = {}

marks.CURRENT = COLORS.blue
marks.VOLTAGE = COLORS.red
marks.NODE = COLORS.green

-- A named colour, or `fallback` for none or an unknown name.
function marks.color(name: string?, fallback: string): string
  return if name then COLORS[name] or fallback else fallback
end

-- A filled arrowhead with its tip at (x, y), pointing along (dx, dy).
local function head(c: Canvas, x: number, y: number, dx: number, dy: number, color: string, size: number)
  local bx, by = x - dx * size * 1.6, y - dy * size * 1.6
  local px, py = -dy * size * 0.7, dx * size * 0.7
  canvas.poly(c, { x, y, bx + px, by + py, bx - px, by - py }, true, { fill = color, stroke = "none" })
end

-- An arrowhead on the `from` lead of a part, pointing the way its current is
-- counted (from → to, or the other way when `reverse`), with `text` beside it.
-- Returns the width the text took, so a voltage mark can stay clear of it.
function marks.current(c: Canvas, p: Placement, text: string?, reverse: boolean, color: string): number
  local t = -(p.len / 2 + p.half) / 2
  local dir = if reverse then -1 else 1
  local x, y = symbols.at(p, t + 5 * dir, 0)
  head(c, x, y, p.ux * dir, p.uy * dir, color, 5.5)
  if not text then
    return 0
  end
  local mx, my = symbols.at(p, t, 0)
  if p.horizontal then
    -- Under the lead, starting at the pin and running towards the body, so
    -- it never crosses a wire that turns the corner there.
    local leftToRight = p.ux >= 0
    local px = symbols.at(p, -p.len / 2, 0)
    canvas.text(c, px + (if leftToRight then 8 else -8), my + 17, text, if leftToRight then "start" else "end", { fill = color })
  else
    canvas.text(c, mx - 9, my + 4, text, "end", { fill = color })
  end
  return canvas.width(text)
end

-- `text` on the far side of a part from its caption: below a horizontal part,
-- left of a vertical one. `clear` px are left free next to the part.
-- Returns where the text's row or column is, for polarity signs to share.
local function tag(c: Canvas, p: Placement, text: string?, clear: number, color: string): number
  if p.horizontal then
    local y = p.my + p.wide + 15 + clear
    if text then
      canvas.text(c, p.mx, y, text, "middle", { fill = color })
    end
    return y
  end
  local x = p.mx - p.wide - 9 - clear
  if text then
    canvas.text(c, x, p.my + 4, text, "end", { fill = color })
  end
  return x
end

-- A reading that belongs to a part but has no direction (its power).
function marks.tag(c: Canvas, p: Placement, text: string, clear: number, color: string)
  tag(c, p, text, clear, color)
end

-- `+` by the `from` end and `−` by the `to` end of a part (swapped when
-- `reverse`), with `text` between them: the voltage V(from) − V(to).
function marks.voltage(c: Canvas, p: Placement, text: string?, reverse: boolean, clear: number, color: string)
  local line = tag(c, p, text, clear, color)
  local reach = math.min(p.len / 2 - 4, p.half + 10)
  local half = if text then canvas.width(text) / 2 + 8 else 0
  local style: canvas.TextStyle = { fill = color, bold = true }
  for _, side in { -1, 1 } do
    local glyph = if (side < 0) ~= reverse then "+" else "−"
    local x, y = symbols.at(p, reach * side, 0)
    if p.horizontal then
      -- Along the text's row, outside the text.
      local towards = if x >= p.mx then 1 else -1
      canvas.text(c, p.mx + towards * math.max(math.abs(x - p.mx), half), line, glyph, "middle", style)
    else
      canvas.text(c, line, y + 4, glyph, "end", style)
    end
  end
end

-- `+` at one point, `−` at another and `text` halfway: a voltage between two
-- points that no single part spans. The marks sit beside the line between the
-- points (right of a vertical one, below a horizontal one), clear of
-- whatever is drawn on it.
function marks.between(c: Canvas, ax: number, ay: number, bx: number, by: number, text: string?, color: string)
  local len = math.max(1, math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2))
  local ux, uy = (bx - ax) / len, (by - ay) / len
  local inset = math.min(16, len / 4)
  local style: canvas.TextStyle = { fill = color, bold = true }
  if math.abs(uy) > math.abs(ux) then
    local x = math.max(ax, bx) + 12
    canvas.text(c, x, ay + uy * inset + 4, "+", "start", style)
    canvas.text(c, x, by - uy * inset + 4, "−", "start", style)
    if text then
      canvas.text(c, x, (ay + by) / 2 + 4, text, "start", { fill = color })
    end
  else
    local y = math.max(ay, by) + 17
    canvas.text(c, ax + ux * inset, y, "+", "middle", style)
    canvas.text(c, bx - ux * inset, y, "−", "middle", style)
    if text then
      canvas.text(c, (ax + bx) / 2, y, text, "middle", { fill = color })
    end
  end
end

-- An X over a part: it is out of the circuit being analysed.
function marks.cross(c: Canvas, p: Placement, color: string)
  local t, s = p.half + 8, math.max(p.wide, 8) + 5
  local attrs = { stroke = color, ["stroke-width"] = 2.5, ["stroke-linecap"] = "round" }
  local x1, y1 = symbols.at(p, -t, -s)
  local x2, y2 = symbols.at(p, t, s)
  canvas.line(c, x1, y1, x2, y2, attrs)
  x1, y1 = symbols.at(p, -t, s)
  x2, y2 = symbols.at(p, t, -s)
  canvas.line(c, x1, y1, x2, y2, attrs)
end

-- An X across a whole region.
function marks.crossBox(c: Canvas, x1: number, y1: number, x2: number, y2: number, color: string)
  local attrs = { stroke = color, ["stroke-width"] = 2.5, ["stroke-linecap"] = "round" }
  canvas.line(c, x1, y1, x2, y2, attrs)
  canvas.line(c, x1, y2, x2, y1, attrs)
end

-- A dashed outline around a region, with `text` above its corner: a
-- supernode, the part of the circuit being replaced, and so on.
function marks.highlight(c: Canvas, x1: number, y1: number, x2: number, y2: number, text: string?, color: string)
  canvas.rect(c, x1, y1, x2 - x1, y2 - y1, {
    stroke = color,
    ["stroke-width"] = 1.5,
    ["stroke-dasharray"] = "6 4",
    fill = color,
    ["fill-opacity"] = 0.07,
    rx = 10,
  })
  if text then
    canvas.text(c, x1 + 4, y1 - 6, text, "start", { fill = color })
  end
end

-- A translucent band along `points` (a flat x, y list) with an arrowhead on
-- each stretch: the path a current takes. Drawn under the circuit.
function marks.path(c: Canvas, points: { number }, text: string?, closed: boolean, color: string)
  if #points < 4 then
    return
  end
  canvas.poly(c, points, closed, {
    stroke = color,
    ["stroke-width"] = 7,
    ["stroke-opacity"] = 0.3,
    ["stroke-linejoin"] = "round",
    ["stroke-linecap"] = "round",
  })
  local count = #points / 2
  local labelled = false
  for i = 1, if closed then count else count - 1 do
    local j = i % count + 1
    local ax, ay, bx, by = points[2 * i - 1], points[2 * i], points[2 * j - 1], points[2 * j]
    local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    if len >= 24 then
      local ux, uy = (bx - ax) / len, (by - ay) / len
      -- A quarter of the way along: clear of a part drawn at the middle.
      local mx, my = ax + ux * len * 0.24, ay + uy * len * 0.24
      head(c, mx + ux * 6, my + uy * 6, ux, uy, color, 7)
      if text and not labelled then
        labelled = true
        if math.abs(ux) >= math.abs(uy) then
          canvas.text(c, mx, my + 21, text, "middle", { fill = color })
        else
          canvas.text(c, mx - 12, my + 4, text, "end", { fill = color })
        end
      end
    end
  end
end

-- A mesh current: most of a circle with an arrowhead, `text` in its middle.
function marks.loop(c: Canvas, x: number, y: number, text: string?, clockwise: boolean, color: string)
  local radius = 17
  -- Screen angles (y points down), so a growing angle turns clockwise.
  local turn = if clockwise then 1 else -1
  local from, to = math.rad(110) * turn, math.rad(110 + 290) * turn
  local sx, sy = x + radius * math.cos(from), y + radius * math.sin(from)
  local ex, ey = x + radius * math.cos(to), y + radius * math.sin(to)
  canvas.cover(c, x, y, radius + 3)
  canvas.path(
    c,
    { "M", sx, sy, string.format("A %d %d 0 1 %d", radius, radius, if clockwise then 1 else 0), ex, ey },
    { stroke = color, ["stroke-width"] = 1.5, ["stroke-linecap"] = "round" }
  )
  head(c, ex, ey, -math.sin(to) * turn, math.cos(to) * turn, color, 5.5)
  if text then
    canvas.text(c, x, y + 4, text, "middle", { fill = color })
  end
end

function marks.note(c: Canvas, x: number, y: number, text: string, color: string?)
  canvas.text(c, x, y + 4, text, "middle", { fill = color })
end

-- `text` next to the point (x, y), on a side nothing is drawn on: right, then
-- left, then above (to the upper right when a wire goes up). Labels sharing
-- a point stack upwards, so a probe and a node letter never overprint.
function marks.label(c: Canvas, x: number, y: number, text: string, sides: Sides, color: string?)
  local style: canvas.TextStyle = { fill = color }
  if not sides.right then
    sides.right = true
    canvas.text(c, x + 9, y + 4, text, "start", style)
  elseif not sides.left then
    sides.left = true
    canvas.text(c, x - 9, y + 4, text, "end", style)
  else
    local level = sides.stack or 0
    sides.stack = level + 1
    if sides.up then
      canvas.text(c, x + 7, y - 7 - 15 * level, text, "start", style)
    else
      canvas.text(c, x, y - 9 - 15 * level, text, "middle", style)
    end
  end
end

return marks
