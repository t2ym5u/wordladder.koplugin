-- Difficulty guarantees (docs/dev/TESTING.md, "Difficulty specs").
--
-- A level asks for a target at an exact optimal distance from the start word
-- (Easy 2-3 steps, Medium 4-5, Hard 6-9), for every word length (3, 4, 5)
-- and both languages. This checks the bands, the distance against an
-- independent BFS, that the levels are ordered on average, that every
-- ladder builds quickly and validly, and that a seed gives the same puzzle.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local LEVELS = { "easy", "medium", "hard" }
local BANDS  = { easy = { 2, 3 }, medium = { 4, 5 }, hard = { 6, 9 } }

local function oneLetterDiff(a, b)
    local d = 0
    for i = 1, #a do if a:sub(i, i) ~= b:sub(i, i) then d = d + 1 end end
    return #a == #b and d == 1
end

-- Independent shortest distance: BFS over the puzzle words (the dictionary
-- minus the blocklist), neighbours by wildcard buckets. Buckets are cached
-- per language and length.
local BUCKETS = {}
local function shortest(start, goal, lang)
    local len = #start
    local key = lang .. len
    local buckets = BUCKETS[key]
    if not buckets then
        local dict = dofile(DIR .. "words_" .. lang .. ".lua")
        local Blocklist = dofile(DIR .. "blocklist.lua")
        buckets = {}
        for w in pairs(dict) do
            if #w == len and not Blocklist.isBlocked(w, lang) then
                for i = 1, len do
                    local k = w:sub(1, i - 1) .. "*" .. w:sub(i + 1)
                    buckets[k] = buckets[k] or {}
                    table.insert(buckets[k], w)
                end
            end
        end
        BUCKETS[key] = buckets
    end
    local dist, queue, head = { [start] = 0 }, { start }, 1
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        if cur == goal then return dist[cur] end
        for i = 1, len do
            for _, nb in ipairs(buckets[cur:sub(1, i - 1) .. "*" .. cur:sub(i + 1)] or {}) do
                if dist[nb] == nil then
                    dist[nb] = dist[cur] + 1
                    queue[#queue + 1] = nb
                end
            end
        end
    end
end

describe("Word ladder difficulty", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    teardown(function()
        Board.release()
    end)

    it("the level bands are disjoint and in order", function()
        for i = 2, #LEVELS do
            assert.is_true(BANDS[LEVELS[i - 1]][2] < BANDS[LEVELS[i]][1])
        end
    end)

    -- moved from test_board_spec.lua. The levels used to differ only by the
    -- length of a random walk, and any ladder of 2+ steps was accepted, so
    -- Hard often needed 2 steps.
    it("puts the target at the level's optimal distance band", function()
        for _, lang in ipairs({ "en", "fr" }) do
            for _, len in ipairs(Board.WORD_LENGTHS) do
                for diff, band in pairs(BANDS) do
                    math.randomseed(len * 7 + #diff)
                    for _ = 1, 4 do
                        local b = Board:new{ word_length = len, difficulty = diff, lang = lang }
                        b:newPuzzle()
                        local steps = #b.solution_path - 1
                        local where = ("%s %d %s"):format(lang, len, diff)
                        assert.is_true(steps >= band[1] and steps <= band[2], where .. ": " .. steps)
                        assert.are.equal(steps, shortest(b.start_word, b.end_word, lang), where)
                    end
                end
            end
        end
    end)

    it("the levels are ordered on the average optimal length", function()
        for _, lang in ipairs({ "en", "fr" }) do
            for _, len in ipairs(Board.WORD_LENGTHS) do
                local avg = {}
                for _, diff in ipairs(LEVELS) do
                    local sum = 0
                    for seed = 1, 6 do
                        math.randomseed(1000 + seed)
                        local b = Board:new{ word_length = len, difficulty = diff, lang = lang }
                        b:newPuzzle()
                        sum = sum + #b.solution_path - 1
                    end
                    avg[diff] = sum / 6
                end
                local where = ("%s %d: easy %.1f medium %.1f hard %.1f"):format(
                    lang, len, avg.easy, avg.medium, avg.hard)
                assert.is_true(avg.easy < avg.medium and avg.medium < avg.hard, where)
            end
        end
    end)

    -- moved from test_board_spec.lua ("word graph", 1.2.0): neighbours come
    -- from a cached wildcard-bucket graph instead of a scan of every
    -- same-length word. Every ladder must still be a valid chain of
    -- dictionary words, and generation must stay quick.
    it("builds valid ladders for every length, difficulty and language", function()
        local t0 = os.clock()
        local n = 0
        for _, lang in ipairs{ "en", "fr" } do
            for _, len in ipairs(Board.WORD_LENGTHS) do
                for _, d in ipairs(LEVELS) do
                    for seed = 1, 20 do
                        math.randomseed(seed)
                        local b = Board:new{ word_length = len, difficulty = d, lang = lang }
                        b:newPuzzle()
                        local p = b.solution_path
                        assert.are.equal("playing", b.status)
                        assert.are.equal(b.start_word, p[1])
                        assert.are.equal(b.end_word, p[#p])
                        for i = 2, #p do
                            assert.is_true(oneLetterDiff(p[i - 1], p[i]), p[i - 1] .. ">" .. p[i])
                        end
                        n = n + 1
                    end
                end
            end
        end
        -- was up to ~0.1 s per puzzle before 1.2.0
        assert.is_true((os.clock() - t0) / n < 0.02)
    end)

    -- moved from test_board_spec.lua
    it("gives the same puzzle for the same seed", function()
        for _, lang in ipairs({ "en", "fr" }) do
            for _, diff in ipairs(LEVELS) do
                math.randomseed(1234)
                local a = Board:new{ word_length = 5, difficulty = diff, lang = lang }
                a:newPuzzle()
                math.randomseed(1234)
                local b = Board:new{ word_length = 5, difficulty = diff, lang = lang }
                b:newPuzzle()
                assert.are.same(a.solution_path, b.solution_path)
            end
        end
    end)

    it("never reads the clock to build a puzzle", function()
        local src = assert(io.open(DIR .. "board.lua")):read("*a")
        assert.is_nil(src:find("os%.time"))
        assert.is_nil(src:find("os%.clock"))
        assert.is_nil(src:find("ui/time", 1, true))
    end)
end)
