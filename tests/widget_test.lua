local bar = { text = "", tooltip = "", glyph = "", color = "", visible = false }
local streamCallback = nil
local streamCommand = nil
local shared = {}
local toggledPanels = {}

local events = {
  ['{"event":"status","state":"recording"}'] = { event = "status", state = "recording" },
  ['{"event":"status","state":"idle"}'] = { event = "status", state = "idle" },
  ['{"event":"state","value":"recording"}'] = { event = "state", value = "recording" },
  ['{"event":"state","value":"cancelled"}'] = { event = "state", value = "cancelled" },
  ['{"event":"state","value":"idle"}'] = { event = "state", value = "idle" },
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
    error("unexpected config key: " .. key)
  end,
  json = {
    decode = function(input)
      if events[input] == nil then error("invalid JSON") end
      return events[input]
    end,
  },
  state = {
    set = function(key, value) shared[key] = value end,
  },
  togglePanel = function(id) table.insert(toggledPanels, id) end,
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
  setGlyph = function(value) bar.glyph = value end,
  setGlyphColor = function(value) bar.color = value end,
  setText = function(value) bar.text = value end,
  setTooltip = function(value) bar.tooltip = value end,
  setVisible = function(value) bar.visible = value end,
}

assert(loadfile("hyprdictate/hyprdictate.luau"))()
assert(streamCallback ~= nil, "daemon socket callback was not registered")
assert(streamCommand:find("/run/user/1000/hyprdictate.sock", 1, true),
       "widget must subscribe directly to daemon socket")
assert(streamCommand:find("while true", 1, true), "socket stream must reconnect")
assert(bar.glyph == "microphone" and bar.visible, "initial idle render")
assert(bar.text == "", "idle bar is glyph-only by default")
assert(shared.dictation.state == "idle", "initial state published for panel")

streamCallback('{"event":"status","state":"recording"}')
assert(#toggledPanels == 1 and toggledPanels[1] == "subiqt/hyprdictate:preview",
       "recording edge opens attached preview panel")
streamCallback('{"event":"transcript","text":"hello, world","final":false}')
assert(bar.text == "", "partial transcript must not change bar width")
assert(shared.dictation.preview == "hello, world", "partial published to panel")

streamCallback('{"event":"transcript","text":"say \\"hello\\"\\nnext","final":false}')
assert(shared.dictation.preview == 'say "hello"\nnext',
       "newlines and quotes preserved in panel buffer")
local beforeInvalid = shared.dictation.preview
streamCallback("not-json")
assert(shared.dictation.preview == beforeInvalid, "invalid JSON must not replace preview")

streamCallback('{"event":"status","state":"idle"}')
assert(bar.glyph == "microphone" and bar.text == "", "idle snapshot stays compact")
assert(shared.dictation.preview == "", "idle reconnect clears stale preview")

streamCallback('{"event":"state","value":"recording"}')
assert(#toggledPanels == 2, "new recording opens preview again")
streamCallback('{"event":"transcript","text":"hello, world","final":false}')
streamCallback('{"event":"state","value":"cancelled"}')
assert(bar.glyph == "player-stop", "cancelled glyph")
assert(shared.dictation.preview == "", "cancel clears panel buffer")

streamCallback('{"event":"state","value":"idle"}')
streamCallback('{"event":"transcript","text":"final, text","final":true}')
assert(shared.dictation.final == "final, text", "final transcript published")
assert(bar.text == "", "final transcript never renders inline")
