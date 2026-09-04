local state = { text = "", tooltip = "", glyph = "", color = "", visible = false }
local streamCallback = nil

local function decodeJsonString(input)
  if input == '[{"instance":"test"}]' then
    return { { instance = "test" } }
  end
  if input:sub(1, 1) ~= '"' or input:sub(-1) ~= '"' then
    error("invalid JSON string")
  end
  local body = input:sub(2, -2)
  local out = ""
  local i = 1
  while i <= #body do
    local ch = body:sub(i, i)
    if ch ~= "\\" then
      out = out .. ch
      i = i + 1
    else
      local escaped = body:sub(i + 1, i + 1)
      local replacements = { ['"'] = '"', ['\\'] = '\\', n = '\n', r = '\r', t = '\t' }
      if replacements[escaped] == nil then error("unsupported escape") end
      out = out .. replacements[escaped]
      i = i + 2
    end
  end
  return out
end

noctalia = {
  getConfig = function(key)
    if key == "show_state_text" then return false end
    if key == "transcript_preview_length" then return 60 end
    error("unexpected config key: " .. key)
  end,
  json = { decode = decodeJsonString },
  getenv = function(key)
    if key == "XDG_RUNTIME_DIR" then return "/run/user/1000" end
    return nil
  end,
  runAsync = function(command, callback)
    if command == "hyprctl instances -j" then
      callback({ exitCode = 0, stdout = '[{"instance":"test"}]' })
    end
  end,
  runStream = function(_, callback) streamCallback = callback end,
}

barWidget = {
  setGlyph = function(value) state.glyph = value end,
  setGlyphColor = function(value) state.color = value end,
  setText = function(value) state.text = value end,
  setTooltip = function(value) state.tooltip = value end,
  setVisible = function(value) state.visible = value end,
}

assert(loadfile("hyprdictate/hyprdictate.luau"))()
assert(streamCallback ~= nil, "socket2 callback was not registered")
assert(state.glyph == "microphone" and state.visible, "initial idle render")

streamCallback("hyprdictate>>state,recording")
streamCallback('hyprdictate>>partial,"hello, world"')
assert(state.text == "hello, world", "comma-containing partial")

streamCallback('hyprdictate>>partial,"say \\"hello\\"\\nnext"')
assert(state.text == 'say "hello"\nnext', "escaped quote/newline partial")
local beforeInvalid = state.text
streamCallback("hyprdictate>>partial,not-json")
assert(state.text == beforeInvalid, "invalid JSON must not replace preview")

streamCallback("hyprdictate>>state,cancelled")
assert(state.glyph == "player-stop", "cancelled glyph")
assert(state.text == "", "cancel clears live preview")

streamCallback("hyprdictate>>state,idle")
streamCallback('hyprdictate>>transcript,"final, text"')
assert(state.tooltip:find("final, text", 1, true), "final transcript in idle tooltip")
