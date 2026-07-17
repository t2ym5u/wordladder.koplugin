local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local WORDS_EN = lrequire("words_en")

local WORD_LENGTHS        = { 3, 4, 5 }
local DEFAULT_WORD_LENGTH = 4
local DEFAULT_DIFFICULTY  = "easy"
local DIFFICULTY_STEPS    = { easy = 3, medium = 5, hard = 7 }
local GENERATE_ATTEMPTS   = 20

-- Only EN is bundled for v1 -- word_length/lang stay separate fields so a
-- future words_fr.lua can be dropped in without changing the board API.
local function dictionaryFor(lang)
    return WORDS_EN
end

local function wordsOfLength(len, lang)
    local dict = dictionaryFor(lang)
    local list = {}
    for w, _ in pairs(dict) do
        if #w == len then list[#list + 1] = w end
    end
    return list
end

local function oneLetterDiff(a, b)
    if #a ~= #b then return false end
    local diff = 0
    for i = 1, #a do
        if a:sub(i, i) ~= b:sub(i, i) then
            diff = diff + 1
            if diff > 1 then return false end
        end
    end
    return diff == 1
end

-- Brute-force scan: cheap at these list sizes (<= ~850 same-length words),
-- no precomputed adjacency structure needed or serialized.
local function neighbors(word, word_list)
    local out = {}
    for _, w in ipairs(word_list) do
        if w ~= word and oneLetterDiff(word, w) then
            out[#out + 1] = w
        end
    end
    return out
end

-- BFS shortest path from `start` to `goal` over the word graph implied by
-- `word_list` (edges = one-letter-diff). Returns an array of words
-- start..goal inclusive, or nil if unreachable.
local function bfsPath(start, goal, word_list)
    if start == goal then return { start } end
    local prev = { [start] = false }
    local queue = { start }
    local head = 1
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        for _, nb in ipairs(neighbors(cur, word_list)) do
            if prev[nb] == nil then
                prev[nb] = cur
                if nb == goal then
                    local path = { goal }
                    local node = goal
                    while prev[node] do
                        node = prev[node]
                        table.insert(path, 1, node)
                    end
                    return path
                end
                queue[#queue + 1] = nb
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- WordLadderBoard
-- ---------------------------------------------------------------------------

local WordLadderBoard = {}
WordLadderBoard.__index = WordLadderBoard

WordLadderBoard.WORD_LENGTHS        = WORD_LENGTHS
WordLadderBoard.DEFAULT_WORD_LENGTH = DEFAULT_WORD_LENGTH
WordLadderBoard.DEFAULT_DIFFICULTY  = DEFAULT_DIFFICULTY

function WordLadderBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        word_length   = opts.word_length or DEFAULT_WORD_LENGTH,
        difficulty    = opts.difficulty or DEFAULT_DIFFICULTY,
        lang          = opts.lang or "en",
        start_word    = nil,
        end_word      = nil,
        solution_path = nil,
        chain         = {},
        current       = {},
        status        = "playing",
        hints_used    = 0,
        wins          = 0,
    }, self)
    return obj
end

-- Random-walk from a random start word (avoiding immediate revisits) for
-- target_steps hops, then re-derive the true shortest path via BFS so
-- solution_path/getHint always reflect an optimal route, not the (possibly
-- longer) walk that discovered the end word. Retries up to
-- GENERATE_ATTEMPTS times if a walk dead-ends too early; falls back to any
-- directly-connected pair if every attempt fails.
function WordLadderBoard:newPuzzle(word_length, difficulty, lang)
    self.word_length = word_length or self.word_length
    self.difficulty  = difficulty or self.difficulty
    self.lang        = lang or self.lang

    local word_list     = wordsOfLength(self.word_length, self.lang)
    local target_steps  = DIFFICULTY_STEPS[self.difficulty] or DIFFICULTY_STEPS.easy

    local best_start, best_end, best_path
    if #word_list >= 2 then
        for _ = 1, GENERATE_ATTEMPTS do
            local start = word_list[math.random(#word_list)]
            local cur = start
            local visited = { [start] = true }
            local last_new = start
            for _ = 1, target_steps do
                local candidates = {}
                for _, nb in ipairs(neighbors(cur, word_list)) do
                    if not visited[nb] then candidates[#candidates + 1] = nb end
                end
                if #candidates == 0 then break end
                cur = candidates[math.random(#candidates)]
                visited[cur] = true
                last_new = cur
            end
            if last_new ~= start then
                local path = bfsPath(start, last_new, word_list)
                if path and #path >= 2 then
                    best_start, best_end, best_path = start, last_new, path
                    if #path - 1 >= math.min(2, target_steps) then break end
                end
            end
        end

        if not best_start then
            for _, w in ipairs(word_list) do
                local nbs = neighbors(w, word_list)
                if #nbs > 0 then
                    best_start, best_end = w, nbs[1]
                    best_path = { w, nbs[1] }
                    break
                end
            end
        end
    end

    self.start_word    = best_start
    self.end_word       = best_end
    self.solution_path  = best_path
    self.chain          = best_start and { best_start } or {}
    self.current         = {}
    self.status          = best_start and "playing" or "no_puzzle"
    self.hints_used       = 0
end

function WordLadderBoard:typeLetter(ch)
    if self.status ~= "playing" then return end
    if #self.current >= self.word_length then return end
    self.current[#self.current + 1] = ch:lower()
end

function WordLadderBoard:deleteLetter()
    if #self.current == 0 then return end
    table.remove(self.current)
end

-- Submits self.current as the next ladder word. Returns one of:
-- "ok" | "won" | "invalid_length" | "not_one_letter_diff" |
-- "not_in_dictionary" | "already_used" | "not_playing"
function WordLadderBoard:submit()
    if self.status ~= "playing" then return "not_playing" end
    if #self.current ~= self.word_length then return "invalid_length" end

    local word = table.concat(self.current)
    local prev = self.chain[#self.chain]
    if not oneLetterDiff(prev, word) then
        return "not_one_letter_diff"
    end
    if not dictionaryFor(self.lang)[word] then
        return "not_in_dictionary"
    end
    for _, w in ipairs(self.chain) do
        if w == word then return "already_used" end
    end

    self.chain[#self.chain + 1] = word
    self.current = {}
    if word == self.end_word then
        self.status = "won"
        self.wins = self.wins + 1
        return "won"
    end
    return "ok"
end

function WordLadderBoard:undoLastWord()
    if #self.chain <= 1 then return false end
    table.remove(self.chain)
    self.status = "playing"
    return true
end

-- Returns the next word on an optimal solution path from the current chain
-- tip, or nil if already at the end word or no solution path is known.
function WordLadderBoard:getHint()
    if not self.solution_path then return nil end
    local step = #self.chain + 1
    local hint = self.solution_path[step]
    if hint then self.hints_used = self.hints_used + 1 end
    return hint
end

function WordLadderBoard:isSolved()
    return self.status == "won"
end

function WordLadderBoard:serialize()
    return {
        word_length   = self.word_length,
        difficulty    = self.difficulty,
        lang          = self.lang,
        start_word    = self.start_word,
        end_word      = self.end_word,
        solution_path = self.solution_path,
        chain         = self.chain,
        status        = self.status,
        hints_used    = self.hints_used,
        wins          = self.wins,
    }
end

function WordLadderBoard:load(data)
    if type(data) ~= "table" or not data.start_word or not data.end_word or not data.chain then
        return false
    end
    self.word_length   = data.word_length or DEFAULT_WORD_LENGTH
    self.difficulty    = data.difficulty or DEFAULT_DIFFICULTY
    self.lang          = data.lang or "en"
    self.start_word     = data.start_word
    self.end_word        = data.end_word
    self.solution_path   = data.solution_path
    self.chain           = data.chain
    -- Never resume a mid-typed word -- KOReader can suspend the app at any
    -- point, and a half-entered guess isn't meaningful game state.
    self.current           = {}
    self.status             = data.status or "playing"
    self.hints_used          = data.hints_used or 0
    self.wins                = data.wins or 0
    return true
end

return WordLadderBoard
