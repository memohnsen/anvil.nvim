local forge_popup = require("anvil.popups.forge")

local function action_keys(popup)
  local keys = {}

  for _, group in ipairs(popup.state.actions) do
    for _, action in ipairs(group) do
      if action.keys then
        for _, key in ipairs(action.keys) do
          table.insert(keys, key)
        end
      end
    end
  end

  table.sort(keys)
  return keys
end

describe("forge popup", function()
  it("uses Forge-compatible dispatch keys", function()
    local popup = forge_popup.create({})

    assert.are.same({
      "VS",
      "Vc",
      "Vs",
      "bF",
      "bI",
      "bP",
      "bb",
      "bf",
      "br",
      "bt",
      "cP",
      "cd",
      "ci",
      "cp",
      "ff",
      "fn",
      "ld",
      "li",
      "ln",
      "lp",
      "lt",
      "pD",
      "pR",
      "pV",
      "pa",
      "pm",
      "pr",
      "pv",
      "t*",
      "tD",
      "tM",
      "tN",
      "t_",
      "ta",
      "tb",
      "tc",
      "td",
      "te",
      "tl",
      "tm",
      "tn",
      "tr",
      "ts",
      "tu",
    }, action_keys(popup))

    popup:close()
  end)
end)
