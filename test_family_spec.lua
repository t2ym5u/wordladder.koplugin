-- Family-friendly words: the game is also played at a family table, so the
-- words it shows by itself (start, target, the solution path behind the
-- hints) must never be one of blocklist.lua's vulgar, sexual, scatological,
-- slur or drug-related words. They stay in the dictionary: a player may still
-- step through one.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local Blocklist = dofile(DIR .. "blocklist.lua")

describe("family-friendly puzzles", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    it("the dictionaries do carry blocklisted words (so the filter is exercised)", function()
        local fr = dofile(DIR .. "words_fr.lua")
        assert.is_not_nil(fr.caca)
    end)

    for _, lang in ipairs({ "en", "fr" }) do
        for _, len in ipairs({ 3, 4, 5 }) do
            it("never shows a blocklisted word (" .. lang .. ", " .. len .. " letters)", function()
                math.randomseed(len * 101)
                for _ = 1, 25 do
                    local b = Board:new({ lang = lang, word_length = len, difficulty = "hard" })
                    b:newPuzzle()
                    for _, w in ipairs(b.solution_path or {}) do
                        assert.is_false(Blocklist.isBlocked(w, lang), w)
                    end
                    assert.is_false(Blocklist.isBlocked(b.start_word, lang))
                    assert.is_false(Blocklist.isBlocked(b.end_word, lang))
                end
            end)
        end
    end

    -- The English list used to carry names, brands and abbreviations (629
    -- words outside the ENABLE dictionary), which the game drew as puzzles.
    it("the English list has no first names, places, brands or abbreviations", function()
        local en = dofile(DIR .. "words_en.lua")
        for _, w in ipairs({ "aaron", "susan", "allah", "jesus", "cairo", "buick", "bosch",
                             "amex", "aclu", "asap", "acct", "clit", "negro", "twink" }) do
            assert.is_nil(en[w], w)
        end
        assert.is_true(en.cat and en.word and en.email and true)
    end)
end)
