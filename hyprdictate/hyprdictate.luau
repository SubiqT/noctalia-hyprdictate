--!nonstrict

-- Hyprdictate bar control. Live hypotheses are published through the plugin's
-- shared state and rendered by the attached preview panel, never inline in the
-- bar, so transcript growth cannot change bar spacing.

local PANEL_ID = "subiqt/hyprdictate:preview"
local STATE_KEY = "dictation"

local STATES = {
  idle = { glyph = "microphone", color = "primary" },
  recording = { glyph = "player-record-filled", color = "error" },
  transcribing = { glyph = "dots", color = "secondary" },
  error = { glyph = "alert-triangle", color = "error" },
  cancelled = { glyph = "player-stop", color = "outline" },
}

local DISPLAY_NAME = {
  idle = "Idle",
  recording = "Recording",
  transcribing = "Transcribing",
  error = "Error",
  cancelled = "Cancelled",
}

local showStateText = noctalia.getConfig("show_state_text")
local currentState = "idle"
local currentPreview = ""
local lastTranscript = ""
local revision = 0

local function publish()
  revision = revision + 1
  noctalia.state.set(STATE_KEY, {
    state = currentState,
    preview = currentPreview,
    final = lastTranscript,
    revision = revision,
  })
end

local function render()
  local state = STATES[currentState] or STATES.idle
  local display = DISPLAY_NAME[currentState] or currentState

  barWidget.setGlyph(state.glyph)
  barWidget.setGlyphColor(state.color)
  barWidget.setText(showStateText and display or "")
  barWidget.setTooltip(
    "hyprdictate: " .. display ..
    " · left click to toggle, right click to cancel"
  )
  barWidget.setVisible(true)
  publish()
end

local function setState(nextState, fromSnapshot)
  local enteringRecording = nextState == "recording" and currentState ~= "recording"

  if enteringRecording then
    currentPreview = ""
  elseif nextState == "cancelled" or nextState == "error" then
    currentPreview = ""
  elseif fromSnapshot and nextState == "idle" then
    currentPreview = ""
    lastTranscript = ""
  end

  currentState = nextState
  render()

  -- The panel closes itself on Idle/Cancelled/Error. Opening only on the
  -- Recording edge keeps toggle semantics deterministic and also covers
  -- keyboard-started sessions, not just clicks on the bar widget.
  if enteringRecording then
    noctalia.togglePanel(PANEL_ID)
  end
end

local function onLine(line)
  local ok, event = pcall(noctalia.json.decode, line)
  if not ok or type(event) ~= "table" then return end

  if event.event == "status" and type(event.state) == "string"
      and STATES[event.state] ~= nil then
    setState(event.state, true)
    return
  end

  if event.event == "state" and type(event.value) == "string"
      and STATES[event.value] ~= nil then
    setState(event.value, false)
    return
  end

  if event.event == "transcript" and type(event.text) == "string" then
    currentPreview = event.text
    if event.final == true then lastTranscript = event.text end
    render()
  end
end

local function shellQuote(value)
  return "'" .. value:gsub("'", "'\"'\"'") .. "'"
end

local xdgRuntime = noctalia.getenv("XDG_RUNTIME_DIR")
if xdgRuntime ~= nil and xdgRuntime ~= "" then
  local socketPath = xdgRuntime .. "/hyprdictate.sock"
  local script = "while true; do stdbuf -oL nc -U " ..
                 shellQuote(socketPath) .. "; sleep 1; done"
  noctalia.runStream("sh -c " .. shellQuote(script), onLine)
end

render()

function onClick()
  noctalia.runAsync("hyprctl dispatch 'hl.plugin.hyprdictate.toggle()'")
end

function onRightClick()
  noctalia.runAsync("hyprctl dispatch 'hl.plugin.hyprdictate.cancel()'")
end
