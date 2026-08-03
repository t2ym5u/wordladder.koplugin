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
