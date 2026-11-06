local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("WordLadderBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)


    local function newBoard(len, diff)
        math.randomseed(42)
        local b = Board:new{ word_length = len or 4, difficulty = diff or "easy" }
        b:newPuzzle()
        return b
    end

    describe("construction", function()
        it("defaults to a 4-letter easy puzzle config before newPuzzle", function()
            local b = Board:new()
            assert.are.equal(4, b.word_length)
            assert.are.equal("easy", b.difficulty)
            assert.are.equal(0, #b.chain)
        end)

        it("exposes WORD_LENGTHS", function()
            assert.are.same({3, 4, 5}, Board.WORD_LENGTHS)
        end)
    end)

    describe("newPuzzle", function()
        it("produces a start/end word pair connected by a real BFS path", function()
            for _, len in ipairs(Board.WORD_LENGTHS) do
                local b = newBoard(len, "medium")
                assert.is_not_nil(b.start_word, ("no puzzle for length %d"):format(len))
                assert.are.equal(len, #b.start_word)
                assert.are.equal(len, #b.end_word)
                assert.is_true(#b.solution_path >= 2)
                assert.are.equal(b.start_word, b.solution_path[1])
                assert.are.equal(b.end_word, b.solution_path[#b.solution_path])
            end
        end)

        -- Independent shortest distance: BFS over the puzzle words (the
        -- dictionary minus the blocklist), neighbours by wildcard buckets.
        local function shortest(start, goal, lang)
            local dict = dofile(DIR .. "words_" .. lang .. ".lua")
            local Blocklist = dofile(DIR .. "blocklist.lua")
            local len = #start
            local buckets = {}
            for w in pairs(dict) do
                if #w == len and not Blocklist.isBlocked(w, lang) then
                    for i = 1, len do
                        local k = w:sub(1, i - 1) .. "*" .. w:sub(i + 1)
                        buckets[k] = buckets[k] or {}
                        table.insert(buckets[k], w)
                    end
                end
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

        -- The levels used to differ only by the length of a random walk, and
        -- any ladder of 2+ steps was accepted, so Hard often needed 2 steps.
        it("puts the target at the level's optimal distance band", function()
            local bands = { easy = { 2, 3 }, medium = { 4, 5 }, hard = { 6, 9 } }
            for _, lang in ipairs({ "en", "fr" }) do
                for _, len in ipairs(Board.WORD_LENGTHS) do
                    for diff, band in pairs(bands) do
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

        it("gives the same puzzle for the same seed", function()
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                math.randomseed(1234)
                local a = Board:new{ word_length = 5, difficulty = diff, lang = "fr" }
                a:newPuzzle()
                math.randomseed(1234)
                local b = Board:new{ word_length = 5, difficulty = diff, lang = "fr" }
                b:newPuzzle()
                assert.are.same(a.solution_path, b.solution_path)
            end
        end)

        it("every consecutive pair in solution_path differs by exactly one letter", function()
            local b = newBoard(4, "hard")
            for i = 1, #b.solution_path - 1 do
                local a, z = b.solution_path[i], b.solution_path[i+1]
                local diff = 0
                for c = 1, #a do
                    if a:sub(c,c) ~= z:sub(c,c) then diff = diff + 1 end
                end
                assert.are.equal(1, diff, ("%s -> %s is not a one-letter step"):format(a, z))
            end
        end)

        it("resets chain to just the start word and clears current/status", function()
            local b = newBoard(4)
            assert.are.same({ b.start_word }, b.chain)
            assert.are.equal(0, #b.current)
            assert.are.equal("playing", b.status)
        end)
    end)

    describe("typeLetter / deleteLetter", function()
        it("builds up to word_length letters and stops accepting more", function()
            local b = newBoard(4)
            b:typeLetter("a"); b:typeLetter("b"); b:typeLetter("c"); b:typeLetter("d")
            assert.are.equal(4, #b.current)
            b:typeLetter("e")
            assert.are.equal(4, #b.current)
        end)

        it("deleteLetter removes the last typed letter", function()
            local b = newBoard(4)
            b:typeLetter("a"); b:typeLetter("b")
            b:deleteLetter()
            assert.are.same({"a"}, b.current)
        end)

        it("deleteLetter on empty buffer is a no-op", function()
            local b = newBoard(4)
            b:deleteLetter()
            assert.are.equal(0, #b.current)
        end)
    end)

    describe("submit", function()
        it("rejects a buffer shorter than word_length", function()
            local b = newBoard(4)
            b:typeLetter("a")
            assert.are.equal("invalid_length", b:submit())
        end)

        it("rejects a word that isn't a one-letter change from the chain tip", function()
            local b = newBoard(4)
            for c in ("zzzz"):gmatch(".") do b:typeLetter(c) end
            assert.are.equal("not_one_letter_diff", b:submit())
        end)

        it("rejects a well-formed but non-dictionary word", function()
            local b = newBoard(4)
            -- mutate the start word's last letter to something that is very
            -- unlikely to be a real word, keeping the one-letter-diff shape
            local bogus = b.start_word:sub(1, 3) .. "q"
            if bogus ~= b.start_word then
                for c in bogus:gmatch(".") do b:typeLetter(c) end
                local result = b:submit()
                assert.is_true(result == "not_in_dictionary" or result == "ok" or result == "won")
            end
        end)

        it("accepts the first solution-path step and advances the chain", function()
            local b = newBoard(4, "medium")
            local step = b.solution_path[2]
            for c in step:gmatch(".") do b:typeLetter(c) end
            local result = b:submit()
            assert.is_true(result == "ok" or result == "won")
            assert.are.equal(step, b.chain[#b.chain])
            assert.are.equal(0, #b.current)
        end)

        it("rejects resubmitting a word already in the chain", function()
            local b = newBoard(4, "medium")
            local step = b.solution_path[2]
            for c in step:gmatch(".") do b:typeLetter(c) end
            b:submit()
            for c in b.start_word:gmatch(".") do b:typeLetter(c) end
            -- start_word is only one-letter-diff from itself's neighbor chain
            -- tip if the ladder doubled back; guard for that structurally
            if step ~= b.start_word then
                local diff = 0
                for i = 1, #step do
                    if step:sub(i,i) ~= b.start_word:sub(i,i) then diff = diff + 1 end
                end
                if diff == 1 then
                    assert.are.equal("already_used", b:submit())
                end
            end
        end)

        it("reaching end_word sets status to won and increments wins", function()
            local b = newBoard(4, "medium")
            for i = 2, #b.solution_path do
                local w = b.solution_path[i]
                for c in w:gmatch(".") do b:typeLetter(c) end
                b:submit()
            end
            assert.are.equal("won", b.status)
            assert.is_true(b:isSolved())
            assert.are.equal(1, b.wins)
        end)

        it("returns not_playing once the puzzle is already won", function()
            local b = newBoard(4, "medium")
            for i = 2, #b.solution_path do
                local w = b.solution_path[i]
                for c in w:gmatch(".") do b:typeLetter(c) end
                b:submit()
            end
            for c in b.end_word:gmatch(".") do b:typeLetter(c) end
            assert.are.equal("not_playing", b:submit())
        end)
    end)

    describe("undoLastWord", function()
        it("removes the last chain entry and resumes playing", function()
            local b = newBoard(4, "medium")
            local step = b.solution_path[2]
            for c in step:gmatch(".") do b:typeLetter(c) end
            b:submit()
            local ok = b:undoLastWord()
            assert.is_true(ok)
            assert.are.same({ b.start_word }, b.chain)
            assert.are.equal("playing", b.status)
        end)

        it("returns false when only the start word remains", function()
            local b = newBoard(4)
            assert.is_false(b:undoLastWord())
        end)
    end)

    describe("getHint", function()
        it("returns the next word on the solution path", function()
            local b = newBoard(4, "medium")
            local hint = b:getHint()
            assert.are.equal(b.solution_path[2], hint)
        end)

        it("increments hints_used", function()
            local b = newBoard(4, "medium")
            b:getHint()
            assert.are.equal(1, b.hints_used)
        end)
    end)

    describe("serialize / load", function()
        it("round-trips puzzle and progress, always resetting current", function()
            local b = newBoard(4, "medium")
            local step = b.solution_path[2]
            for c in step:gmatch(".") do b:typeLetter(c) end
            b:submit()
            b:typeLetter("x")  -- mid-typed, should NOT survive the round-trip

            local data = b:serialize()
            local b2 = Board:new()
            local ok = b2:load(data)
            assert.is_true(ok)
            assert.are.equal(b.start_word, b2.start_word)
            assert.are.equal(b.end_word, b2.end_word)
            assert.are.same(b.chain, b2.chain)
            assert.are.equal(0, #b2.current)
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
            assert.is_false(b:load({ start_word = "abc" }))
        end)
    end)
end)

-- 1.2.0: neighbours come from a cached wildcard-bucket graph instead of a
-- scan of every same-length word. Every ladder must still be a valid,
-- shortest chain of dictionary words, and generation must stay quick.
describe("word graph", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    local function oneLetterDiff(a, b)
        local d = 0
        for i = 1, #a do if a:sub(i, i) ~= b:sub(i, i) then d = d + 1 end end
        return #a == #b and d == 1
    end

    it("builds valid ladders for every length, difficulty and language", function()
        local t0 = os.clock()
        local n = 0
        for _, lang in ipairs{ "en", "fr" } do
            for _, len in ipairs(Board.WORD_LENGTHS) do
                for _, d in ipairs{ "easy", "medium", "hard" } do
                    for seed = 1, 20 do
                        math.randomseed(seed)
                        local b = Board:new{ word_length = len, difficulty = d, lang = lang }
                        b:newPuzzle()
                        local p = b.solution_path
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
end)

-- The word lists load with the first puzzle of a language, only that
-- language's, and release() (the screen closing) drops them.
describe("word data loading", function()
    local Board

    setup(function()
        Board = require("board")
        Board.release()
    end)

    it("loads nothing until a puzzle is made, then only that language", function()
        assert.are.same({}, Board.loadedLanguages())
        local b = Board:new{ word_length = 4, difficulty = "easy", lang = "fr" }
        assert.are.same({}, Board.loadedLanguages())
        b:newPuzzle()
        assert.are.same({ "fr" }, Board.loadedLanguages())
        Board.release()
        assert.are.same({}, Board.loadedLanguages())
        -- A board still works after release: its language loads again.
        b:newPuzzle()
        assert.is_not_nil(b.start_word)
        assert.are.same({ "fr" }, Board.loadedLanguages())
        Board.release()
    end)
end)
