--!nonstrict

-- Live Moonshine transcript preview for hyprdictate. This widget subscribes
-- directly to the daemon's line-delimited JSON socket so partial hypotheses do
-- not depend on compositor event forwarding. Final text remains the only text
-- injected into applications by the Hyprland plugin.

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
local previewLength = tonumber(noctalia.getConfig("transcript_preview_length")) or 60
if previewLength < 1 then previewLength = 1 end

local currentState = "idle"
local currentPreview = ""
local lastTranscript = ""

local function truncate(text)
  if #text <= previewLength then return text end
  return text:sub(1, previewLength) .. "…"
end

local function render()
  local state = STATES[currentState] or STATES.idle
  local display = DISPLAY_NAME[currentState] or currentState
  local live = ""
  if currentState == "recording" or currentState == "transcribing" then
    live = currentPreview
  end

  barWidget.setGlyph(state.glyph)
  barWidget.setGlyphColor(state.color)
  barWidget.setText(live ~= "" and truncate(live)
                    or (showStateText and display or ""))

  local detail = live
  if detail == "" and currentState == "idle" then detail = lastTranscript end
  local tooltip = "hyprdictate: " .. display
  if detail ~= "" then tooltip = tooltip .. " · " .. truncate(detail) end
  tooltip = tooltip .. " · left click to toggle, right click to cancel"
  barWidget.setTooltip(tooltip)
  barWidget.setVisible(true)
end

local function onLine(line)
  local ok, event = pcall(noctalia.json.decode, line)
  if not ok or type(event) ~= "table" then return end

  if event.event == "status" and type(event.state) == "string"
      and STATES[event.state] ~= nil then
    currentState = event.state
    currentPreview = ""
    if currentState == "idle" then lastTranscript = "" end
    render()
    return
  end

  if event.event == "state" and type(event.value) == "string"
      and STATES[event.value] ~= nil then
    if event.value == "recording" and currentState ~= "recording" then
      currentPreview = ""
    elseif event.value == "cancelled" or event.value == "error" then
      currentPreview = ""
    end
    currentState = event.value
    render()
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
  -- The daemon and shell start independently during a graphical-session
  -- switch. Reconnect once a second whenever nc exits so whichever starts
  -- first eventually observes the other without reloading Noctalia.
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
