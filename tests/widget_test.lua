local state = { text = "", tooltip = "", glyph = "", color = "", visible = false }
local streamCallback = nil
local streamCommand = nil

local events = {
  ['{"event":"status","state":"recording"}'] = {
    event = "status", state = "recording",
  },
  ['{"event":"status","state":"idle"}'] = {
    event = "status", state = "idle",
  },
  ['{"event":"state","value":"recording"}'] = {
    event = "state", value = "recording",
  },
  ['{"event":"state","value":"cancelled"}'] = {
    event = "state", value = "cancelled",
  },
  ['{"event":"state","value":"idle"}'] = {
    event = "state", value = "idle",
  },
  ['{"event":"transcript","text":"hello, world","final":false}'] = {
    event = "transcript", text = "hello, world", final = false,
  },
  ['{"event":"transcript","text":"say \\"hello\\"\\nnext","final":false}'] = {
    event = "transcript", text = 'say "hello"\nnext', final = false,
  },
  ['{"event":"transcript","text":"final, text","final":true}'] = {
    event = "transcript", text = "final, text", final = true,
  },
}

noctalia = {
  getConfig = function(key)
    if key == "show_state_text" then return false end
    if key == "transcript_preview_length" then return 60 end
    error("unexpected config key: " .. key)
  end,
  json = {
    decode = function(input)
      if events[input] == nil then error("invalid JSON") end
      return events[input]
    end,
  },
  getenv = function(key)
    if key == "XDG_RUNTIME_DIR" then return "/run/user/1000" end
    return nil
  end,
  runAsync = function() end,
  runStream = function(command, callback)
    streamCommand = command
    streamCallback = callback
  end,
}

barWidget = {
  setGlyph = function(value) state.glyph = value end,
  setGlyphColor = function(value) state.color = value end,
  setText = function(value) state.text = value end,
  setTooltip = function(value) state.tooltip = value end,
  setVisible = function(value) state.visible = value end,
}

assert(loadfile("hyprdictate/hyprdictate.luau"))()
assert(streamCallback ~= nil, "daemon socket callback was not registered")
assert(streamCommand:find("/run/user/1000/hyprdictate.sock", 1, true),
       "widget must subscribe directly to daemon socket")
assert(streamCommand:find("while true", 1, true), "socket stream must reconnect")
assert(state.glyph == "microphone" and state.visible, "initial idle render")

streamCallback('{"event":"status","state":"recording"}')
streamCallback('{"event":"transcript","text":"hello, world","final":false}')
assert(state.text == "hello, world", "partial visible after recording reconnect snapshot")

streamCallback('{"event":"transcript","text":"say \\"hello\\"\\nnext","final":false}')
assert(state.text == 'say "hello"\nnext', "escaped quote/newline partial")
local beforeInvalid = state.text
streamCallback("not-json")
assert(state.text == beforeInvalid, "invalid JSON must not replace preview")

streamCallback('{"event":"status","state":"idle"}')
assert(state.glyph == "microphone" and state.text == "",
       "idle reconnect snapshot clears stale preview")
streamCallback('{"event":"state","value":"recording"}')
streamCallback('{"event":"transcript","text":"hello, world","final":false}')

streamCallback('{"event":"state","value":"cancelled"}')
assert(state.glyph == "player-stop", "cancelled glyph")
assert(state.text == "", "cancel clears live preview")

streamCallback('{"event":"state","value":"idle"}')
streamCallback('{"event":"transcript","text":"final, text","final":true}')
assert(state.tooltip:find("final, text", 1, true), "final transcript in idle tooltip")
