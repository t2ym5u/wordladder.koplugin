local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase           = require("screen_base")
local MenuHelper           = require("menu_helper")
local WordLadderBoard       = lrequire("board")
local WordLadderBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- WordLadderScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Word Ladder — Rules

Change the start word into the target word, one step at a time.

Each step must:
• Change exactly one letter.
• Still be a real word.

Use the on-screen keyboard to enter each next word. Press ↵ to submit, ⌫ to delete.
Use "Hint" to reveal the next word on a shortest solution path, or "Undo" to take back your last step.
]])

local GAME_RULES_FR = [[
Mot en Échelle — Règles

Transformez le mot de départ en mot cible, une étape à la fois.

Chaque étape doit :
• Changer exactement une lettre.
• Rester un mot valide.

Utilisez le clavier à l'écran pour saisir chaque mot suivant. Appuyez sur ↵ pour valider, sur ⌫ pour effacer.
Utilisez "Indice" pour révéler le mot suivant d'une solution optimale, ou "Annuler" pour revenir en arrière.
]]

local WordLadderScreen = ScreenBase:extend{}

local WORD_LENGTH_LABELS = { [3] = "3", [4] = "4", [5] = "5" }
local DIFFICULTY_LABELS  = { easy = _("Easy"), medium = _("Medium"), hard = _("Hard") }
local DIFFICULTY_ORDER   = { "easy", "medium", "hard" }

-- Keyboard rows (letters only -- ↵/⌫ live in a separate utility row so the
-- letter rows stay a clean QWERTY layout regardless of word_length).
local KEY_ROWS = {
    {"Q","W","E","R","T","Y","U","I","O","P"},
    {"A","S","D","F","G","H","J","K","L"},
    {"↵","Z","X","C","V","B","N","M","⌫"},
}

function WordLadderScreen:init()
    local state       = self.plugin:loadState()
    local word_length = self.plugin:getSetting("word_length", WordLadderBoard.DEFAULT_WORD_LENGTH)
    local difficulty  = self.plugin:getSetting("difficulty", WordLadderBoard.DEFAULT_DIFFICULTY)
    self.board = WordLadderBoard:new{ word_length = word_length, difficulty = difficulty }
    if not self.board:load(state) then
        self.board:newPuzzle()
    end
    ScreenBase.init(self)
end

function WordLadderScreen:serializeState()
    return self.board:serialize()
end

function WordLadderScreen:buildLayout()
    local sw = DeviceScreen:getWidth()
    local sh = DeviceScreen:getHeight()
    local is_landscape = self:isLandscape()

    local btn_width = is_landscape
        and math.max(math.floor(sw * 0.38), 120)
        or  math.floor(sw * 0.9)

    local title_bar = self:buildTitleBar(_("Word Ladder"), function()
        return {
            { text = _("New puzzle"),           callback = function() self:onNewPuzzle() end },
            { text = self:_wordLengthLabel(),   callback = function() self:openWordLengthMenu() end },
            { text = self:_difficultyLabel(),   callback = function() self:openDifficultyMenu() end },
            { text = _("Hint"),                 callback = function() self:onHint() end },
            { text = _("Undo"),                 callback = function() self:onUndo() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    local board_h = is_landscape and (sh - 40) or math.floor(sh * 0.45)
    self.board_widget = WordLadderBoardWidget:new{
        board  = self.board,
        width  = btn_width,
        height = math.max(board_h, 120),
    }

    local board_frame = FrameContainer:new{
        padding = Size.padding.default,
        margin  = Size.margin.default,
        self.board_widget,
    }

    local key_rows_cfg = {}
    for _, row in ipairs(KEY_ROWS) do
        local btns = {}
        for _, key in ipairs(row) do
            local k = key
            btns[#btns + 1] = {
                id       = "key_" .. k,
                text     = k,
                callback = function() self:onKeyPress(k) end,
            }
        end
        key_rows_cfg[#key_rows_cfg + 1] = btns
    end
    self.keyboard_widget = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_width,
        buttons = key_rows_cfg,
    }

    if is_landscape then
        local right = VerticalGroup:new{
            align = "center",
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.keyboard_widget,
        }
        local content = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        local footer = VerticalGroup:new{
            align = "center",
            self.keyboard_widget,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self:buildPortraitLayout(title_bar, board_frame, footer)
    end
    self:updateStatus()
end

function WordLadderScreen:onKeyPress(key)
    if key == "↵" then
        local result = self.board:submit()
        if result == "invalid_length" then
            self:updateStatus(_("Not enough letters!"))
            return
        elseif result == "not_one_letter_diff" then
            self:updateStatus(_("Change exactly one letter!"))
            return
        elseif result == "not_in_dictionary" then
            self:updateStatus(_("Not a real word!"))
            return
        elseif result == "already_used" then
            self:updateStatus(_("Already used that word!"))
            return
        end
        self:buildLayout()
        UIManager:setDirty(self, function() return "ui", self.dimen end)
        self.plugin:saveState(self.board:serialize())
    elseif key == "⌫" then
        self.board:deleteLetter()
        self.board_widget:refresh()
        self:updateStatus()
    else
        self.board:typeLetter(key)
        self.board_widget:refresh()
        self:updateStatus()
    end
end

function WordLadderScreen:onNewPuzzle()
    self.board:newPuzzle()
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function WordLadderScreen:onHint()
    local hint = self.board:getHint()
    if hint then
        self:updateStatus(T(_("Hint: %1"), hint:upper()))
    else
        self:updateStatus(_("No hint available."))
    end
    self.plugin:saveState(self.board:serialize())
end

function WordLadderScreen:onUndo()
    local ok = self.board:undoLastWord()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    if ok then
        self:updateStatus(_("Last word undone."))
    else
        self:updateStatus(_("Nothing to undo."))
    end
    self.plugin:saveState(self.board:serialize())
end

function WordLadderScreen:openWordLengthMenu()
    local items = {}
    for _, len in ipairs(WordLadderBoard.WORD_LENGTHS) do
        items[#items + 1] = { id = len, text = WORD_LENGTH_LABELS[len] .. _(" letters") }
    end
    MenuHelper.openPickerMenu{
        title      = _("Word length"),
        items      = items,
        current_id = self.board.word_length,
        parent     = self,
        on_select  = function(len)
            self.plugin:saveSetting("word_length", len)
            self.board = WordLadderBoard:new{ word_length = len, difficulty = self.board.difficulty }
            self.board:newPuzzle()
            self.plugin:saveState(self.board:serialize())
            self:buildLayout()
            UIManager:setDirty(self, function() return "ui", self.dimen end)
        end,
    }
end

function WordLadderScreen:openDifficultyMenu()
    local items = {}
    for _, id in ipairs(DIFFICULTY_ORDER) do
        items[#items + 1] = { id = id, text = DIFFICULTY_LABELS[id] }
    end
    MenuHelper.openPickerMenu{
        title      = _("Difficulty"),
        items      = items,
        current_id = self.board.difficulty,
        parent     = self,
        on_select  = function(id)
            self.plugin:saveSetting("difficulty", id)
            self.board.difficulty = id
            self.board:newPuzzle()
            self.plugin:saveState(self.board:serialize())
            self:buildLayout()
            UIManager:setDirty(self, function() return "ui", self.dimen end)
        end,
    }
end

function WordLadderScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.status == "won" then
        status = T(_("Solved in %1 steps! Wins: %2"), #self.board.chain - 1, self.board.wins)
    elseif self.board.status == "no_puzzle" then
        status = _("No puzzle available for this word length.")
    else
        status = T(_("%1 → %2  (step %3)"),
            self.board.start_word and self.board.start_word:upper() or "",
            self.board.end_word and self.board.end_word:upper() or "",
            #self.board.chain)
    end
    ScreenBase.updateStatus(self, status)
end

function WordLadderScreen:_wordLengthLabel()
    return T(_("Length: %1"), self.board.word_length)
end

function WordLadderScreen:_difficultyLabel()
    return T(_("Difficulty: %1"), DIFFICULTY_LABELS[self.board.difficulty])
end

return WordLadderScreen
