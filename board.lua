local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

-- Word lists are read with loadfile, not lrequire: package.loaded would keep
-- them for the whole session.
local function loadWordList(name)
    return assert(loadfile(_dir .. name .. ".lua"))()
end

local WORD_LENGTHS        = { 3, 4, 5 }
local DEFAULT_WORD_LENGTH = 4
local DEFAULT_DIFFICULTY  = "easy"
-- Each level asks for a target at an exact optimal distance (the fewest
-- steps from the start word): Easy 2-3, Medium 4-5, Hard 6-9. Hard stops
-- at 9 because some 5-letter words sit at the end of long chains (37 steps
-- in English), a chore to type rather than a harder puzzle. When the word
-- graph has no such pair from the start words tried, the puzzle comes as
-- close to the band as it can.
local DIFFICULTY_BANDS    = {
    easy   = { 2, 3 },
    medium = { 4, 5 },
    hard   = { 6, 9 },
}
local GENERATE_ATTEMPTS   = 30

-- A language's word data -- its dictionary (word -> true) and the word graphs
-- built from it (graphFor) -- loads the first time that language is played,
-- not with the module, and only that language's. WordLadderBoard.release()
-- (the screen closing) drops it all: it is quick to build again and only
-- needed while a game is open.
local DATA = {}

local function langData(lang)
    lang = lang == "fr" and "fr" or "en"
    local d = DATA[lang]
    if not d then
        d = { lang = lang, words = loadWordList("words_" .. lang), graphs = {} }
        -- Only one language at a time: switching drops the previous one.
        DATA = { [lang] = d }
    end
    return d
end

local function dictionaryFor(lang)
    return langData(lang).words
end

-- Puzzles (start, target, the solution path and its hints) are built from
-- this list only, so a blocklisted word (blocklist.lua) is never shown --
-- it stays in the dictionary, so a player may still step through it.
local Blocklist = lrequire("blocklist")

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

-- The word graph of one language and length, built on first use and kept
-- until release():
-- the puzzle words (`list`, in the dictionary's iteration order) and, per
-- word, its one-letter neighbours (`adj`). Neighbours come from wildcard
-- buckets ("c_t" -> cat, cot, cut...) instead of scanning the whole list for
-- every visited word, which made a 4-letter Hard ladder take ~0.1 s on a
-- desktop (seconds on a reader), and the list was rebuilt for every puzzle.
-- Neighbours stay in list order, so a seed always picks the same ladder.
local function graphFor(len, lang)
    local d = langData(lang)
    local graphs = d.graphs
    if graphs[len] then return graphs[len] end
    local dict = d.words
    local blocked = Blocklist.set(lang)
    local list, pos = {}, {}
    for w, _ in pairs(dict) do
        if #w == len and not blocked[w:upper()] then
            list[#list + 1] = w
        end
    end
    -- Alphabetical, not the dictionary's hash order: a seed must give the
    -- same ladder on every device and Lua build.
    table.sort(list)
    for i, w in ipairs(list) do pos[w] = i end
    local function bucketKey(w, i) return w:sub(1, i - 1) .. "_" .. w:sub(i + 1) end
    local buckets = {}
    for _, w in ipairs(list) do
        for i = 1, len do
            local k = bucketKey(w, i)
            local bucket = buckets[k]
            if not bucket then bucket = {}; buckets[k] = bucket end
            bucket[#bucket + 1] = w
        end
    end
    local function byPos(x, y) return pos[x] < pos[y] end
    local adj = {}
    for _, w in ipairs(list) do
        -- two distinct words share at most one bucket: no duplicates
        local out = {}
        for i = 1, len do
            for _, nb in ipairs(buckets[bucketKey(w, i)]) do
                if nb ~= w then out[#out + 1] = nb end
            end
        end
        table.sort(out, byPos)
        adj[w] = out
    end
    graphs[len] = { list = list, adj = adj }
    return graphs[len]
end

-- Breadth-first search from `start` over the word graph `adj` (graphFor;
-- edges = one-letter changes). Returns `order` (every reachable word, in
-- visiting order), `dist` (word -> fewest steps from start) and `prev`
-- (word -> the word before it on one shortest path; start -> false).
local function bfsFrom(start, adj)
    local dist, prev = { [start] = 0 }, { [start] = false }
    local order = { start }
    local head = 1
    while head <= #order do
        local cur = order[head]; head = head + 1
        local d = dist[cur] + 1
        for _, nb in ipairs(adj[cur]) do
            if dist[nb] == nil then
                dist[nb], prev[nb] = d, cur
                order[#order + 1] = nb
            end
        end
    end
    return order, dist, prev
end

-- The shortest path start..goal from bfsFrom's `prev`.
local function pathTo(goal, prev)
    local path = { goal }
    local node = goal
    while prev[node] do
        node = prev[node]
        table.insert(path, 1, node)
    end
    return path
end

-- How far `d` steps is from the band { lo, hi } (0 inside it).
local function bandGap(d, band)
    if d < band[1] then return band[1] - d end
    if d > band[2] then return d - band[2] end
    return 0
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

-- Picks a random start word, runs a BFS from it, and takes a random target
-- among the words whose optimal distance falls in the level's band
-- (DIFFICULTY_BANDS). A start whose component never reaches the band is
-- replaced by another, up to GENERATE_ATTEMPTS times; after that the
-- puzzle uses the target closest to the band seen so far, so a small graph
-- still gets its longest ladders on Hard. solution_path is the BFS path, so
-- it is optimal and its length is the puzzle's real difficulty. Uses only
-- math.random: a seed gives the same puzzle every time.
function WordLadderBoard:newPuzzle(word_length, difficulty, lang)
    self.word_length = word_length or self.word_length
    self.difficulty  = difficulty or self.difficulty
    self.lang        = lang or self.lang

    local graph         = graphFor(self.word_length, self.lang)
    local word_list, adj = graph.list, graph.adj
    local band          = DIFFICULTY_BANDS[self.difficulty] or DIFFICULTY_BANDS.easy

    local best_start, best_path, best_gap
    if #word_list >= 2 then
        for _ = 1, GENERATE_ATTEMPTS do
            local start = word_list[math.random(#word_list)]
            local order, dist, prev = bfsFrom(start, adj)
            -- Words in the band; else the ones closest to it.
            local cands, gap = {}, math.huge
            for i = 2, #order do
                local w = order[i]
                local g = bandGap(dist[w], band)
                if g < gap then
                    cands, gap = { w }, g
                elseif g == gap then
                    cands[#cands + 1] = w
                end
            end
            if #cands > 0 and (best_gap == nil or gap < best_gap) then
                local target = cands[math.random(#cands)]
                best_start, best_path, best_gap = start, pathTo(target, prev), gap
                if gap == 0 then break end
            end
        end
    end
    if not best_path then
        -- Every start tried had no neighbour: any connected pair will do.
        for _, w in ipairs(word_list) do
            if #adj[w] > 0 then
                best_start, best_path = w, { w, adj[w][1] }
                break
            end
        end
    end
    local best_end = best_path and best_path[#best_path]

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

-- Drops every loaded dictionary and word graph (called when the game screen
-- closes); the next game reads its language's list again.
function WordLadderBoard.release()
    DATA = {}
    Blocklist.release()
end

-- The languages whose word data is loaded now (for the specs).
function WordLadderBoard.loadedLanguages()
    local out = {}
    for lang in pairs(DATA) do out[#out + 1] = lang end
    table.sort(out)
    return out
end

return WordLadderBoard
