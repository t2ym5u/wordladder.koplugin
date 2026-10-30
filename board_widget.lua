local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local C_BG    = Blitbuffer.COLOR_WHITE
local C_FG    = Blitbuffer.COLOR_BLACK
local C_GRAY  = Blitbuffer.COLOR_GRAY_9

local Screen = Device.screen

-- Rows kept on screen at the comfortable size before the font starts to
-- shrink: target + this many chain words + the typed row.
local COMFORT_ROWS = 8

-- Largest face whose ink for `sample` fits max_w x max_h. Measured unbounded
-- (a max_width limit cuts the text, so the width test could never fail), ink
-- height is y_top + y_bottom, and Font:getFace scales its size by the DPI, so
-- the pixel bound is converted back first.
local function fitFace(name, sample, max_w, max_h)
    local lo = 6
    local hi = math.max(lo, math.floor(max_h * 1000 / Screen:scaleBySize(1000)) * 2)
    local best = lo
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), Font:getFace(name, mid), sample, true, false)
        if m.x <= max_w and m.y_top + m.y_bottom <= max_h then
            best, lo = mid, mid + 1
        else
            hi = mid - 1
        end
    end
    return Font:getFace(name, best)
end

-- ---------------------------------------------------------------------------
-- WordLadderBoardWidget — read-only display of the ladder chain built so
-- far, the current typed buffer, and the target word. All input happens via
-- the on-screen keyboard in screen.lua, so this widget never registers
-- gestures.
-- ---------------------------------------------------------------------------

local WordLadderBoardWidget = InputContainer:extend{
    board  = nil,
    width  = 200,
    height = 200,
}

function WordLadderBoardWidget:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }

    -- Every row gets the same pitch: an eighth of the height (or of the
    -- width, on a very flat board), of which the ink takes 60%. The typed row
    -- spaces its letters ("W _ _ _"), so it is the one measured.
    local n      = self.board.word_length or 4
    local sample = string.rep("W", n, " ")
    self.row_h   = math.floor(math.min(self.height / (COMFORT_ROWS + 1), self.width / 4))
    self.word_face = fitFace("cfont", sample, math.floor(self.width * 0.9), math.floor(self.row_h * 0.6))
    self.info_face = fitFace("smallinfofont", string.rep("W", n),
        math.floor(self.width * 0.9), math.floor(self.row_h * 0.45))
    self.paint_rect = nil
end

function WordLadderBoardWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

-- Draws `text` centred horizontally in [x, x+w] and vertically on cy: the
-- baseline sits half the ink height below cy.
local function centeredText(bb, x, cy, w, face, text, color)
    local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text, true, false)
    local tx = x + math.max(0, math.floor((w - m.x) / 2))
    RenderText:renderUtf8Text(bb, tx, cy + math.floor((m.y_top - m.y_bottom) / 2),
        face, text, true, false, color)
end

function WordLadderBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    bb:paintRect(x, y, self.width, self.height, C_BG)

    local board = self.board
    local w     = self.width
    local row_h = self.row_h
    local playing = board.status == "playing"

    -- Rows: target, the chain, and the typed buffer while playing. A long
    -- ladder keeps its newest words: the oldest ones drop off the top behind
    -- an ellipsis (Undo only ever needs the latest).
    local slots = math.max(2, math.floor(self.height / row_h))
    local avail = slots - 1 - (playing and 1 or 0)
    local first = math.max(1, #board.chain - avail + 1)

    local cy = y + math.floor(row_h / 2)
    -- Target word, shown once at the top.
    centeredText(bb, x, cy, w, self.info_face, (board.end_word or ""):upper(), C_GRAY)
    cy = cy + row_h

    -- Ladder chain built so far, oldest to newest.
    for i = first, #board.chain do
        local word = board.chain[i]
        local won_word = board.status == "won" and word == board.end_word
        local text = word:upper()
        if i == first and first > 1 then text = "… " .. text end
        centeredText(bb, x, cy, w, self.word_face, text, won_word and C_GRAY or C_FG)
        cy = cy + row_h
    end

    -- Current typed buffer (blank cells for untyped letters), only while playing.
    if playing then
        local cells = {}
        for i = 1, board.word_length do
            cells[i] = board.current[i] or "_"
        end
        centeredText(bb, x, cy, w, self.word_face, table.concat(cells, " "):upper(), C_FG)
    end
end

return WordLadderBoardWidget
