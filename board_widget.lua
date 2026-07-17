local Blitbuffer     = require("ffi/blitbuffer")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local C_BG    = Blitbuffer.COLOR_WHITE
local C_FG    = Blitbuffer.COLOR_BLACK
local C_GRAY  = Blitbuffer.COLOR_GRAY_9

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

    local row_size = math.max(12, math.floor(self.height * 0.11))
    self.word_face  = Font:getFace("cfont", row_size)
    local info_size = math.max(10, math.floor(self.height * 0.06))
    self.info_face  = Font:getFace("smallinfofont", info_size)
    self.paint_rect = nil
end

function WordLadderBoardWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

-- Draws `text` centered horizontally at row-top `y`, returns the row's
-- total rendered height (ascent + descent) so callers can stack rows
-- without overlap.
local function centeredText(bb, x, y, w, face, text, color)
    local m = RenderText:sizeUtf8Text(0, w, face, text, true, false)
    local tx = x + math.max(0, math.floor((w - m.x) / 2))
    RenderText:renderUtf8Text(bb, tx, y + m.y_top, face, text, true, false, color)
    return m.y_top + m.y_bottom
end

function WordLadderBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    bb:paintRect(x, y, self.width, self.height, C_BG)

    local board = self.board
    local w = self.width
    -- Row spacing is driven by each row's actual measured glyph height
    -- (ascent + descent) plus a fixed margin, rather than an independently
    -- guessed fraction of self.height -- the latter can end up smaller than
    -- the real font metrics and make consecutive rows overlap.
    local margin = math.max(4, math.floor(self.height * 0.03))
    local cy = y + margin

    -- Target word, shown once at the top.
    cy = cy + centeredText(bb, x, cy, w, self.info_face,
        (board.end_word or ""):upper(), C_GRAY) + margin * 2

    -- Ladder chain built so far, oldest to newest.
    for _, word in ipairs(board.chain) do
        local won_word = board.status == "won" and word == board.end_word
        cy = cy + centeredText(bb, x, cy, w, self.word_face, word:upper(),
            won_word and C_GRAY or C_FG) + margin
    end

    -- Current typed buffer (blank cells for untyped letters), only while playing.
    if board.status == "playing" then
        local cells = {}
        for i = 1, board.word_length do
            cells[i] = board.current[i] or "_"
        end
        centeredText(bb, x, cy, w, self.word_face, table.concat(cells, " "):upper(), C_FG)
    end
end

return WordLadderBoardWidget
