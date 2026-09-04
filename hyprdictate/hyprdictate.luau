--!nonstrict

-- Bar widget for hyprdictate. The Hyprland plugin forwards daemon state and
-- JSON-encoded partial/final transcripts over socket2:
--
--   hyprdictate>>state,<idle|recording|transcribing|error|cancelled>
--   hyprdictate>>partial,"replaceable text"
--   hyprdictate>>transcript,"final text"

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
  if live ~= "" then
    barWidget.setText(truncate(live))
  else
    barWidget.setText(showStateText and display or "")
  end

  local detail = live
  if detail == "" and currentState == "idle" then detail = lastTranscript end
  local tooltip = "hyprdictate: " .. display
  if detail ~= "" then tooltip = tooltip .. " · " .. truncate(detail) end
  tooltip = tooltip .. " · left click to toggle, right click to cancel"
  barWidget.setTooltip(tooltip)
  barWidget.setVisible(true)
end

local function decodeTranscript(payload)
  local ok, value = pcall(noctalia.json.decode, payload)
  if not ok or type(value) ~= "string" then return nil end
  return value
end

local function onLine(line)
  local state = line:match("^hyprdictate>>state,(%a+)")
  if state ~= nil and STATES[state] ~= nil then
    if state == "recording" and currentState ~= "recording" then
      currentPreview = ""
    elseif state == "cancelled" or state == "error" then
      currentPreview = ""
    end
    currentState = state
    render()
    return
  end

  local partial = line:match("^hyprdictate>>partial,(.+)$")
  if partial ~= nil then
    local text = decodeTranscript(partial)
    if text ~= nil then
      currentPreview = text
      render()
    end
    return
  end

  local final = line:match("^hyprdictate>>transcript,(.+)$")
  if final ~= nil then
    local text = decodeTranscript(final)
    if text ~= nil then
      currentPreview = text
      lastTranscript = text
      render()
    end
  end
end

noctalia.runAsync("hyprctl instances -j", function(res)
  if res.exitCode ~= 0 then return end
  local instances = noctalia.json.decode(res.stdout)
  if type(instances) ~= "table" or #instances == 0 then return end
  local sig = instances[1].instance
  if type(sig) ~= "string" or sig == "" then return end

  local xdgRuntime = noctalia.getenv("XDG_RUNTIME_DIR")
  if xdgRuntime == nil or xdgRuntime == "" then return end
  local socketPath = xdgRuntime .. "/hypr/" .. sig .. "/.socket2.sock"
  noctalia.runStream("stdbuf -oL nc -U '" .. socketPath .. "'", onLine)
end)

render()

function onClick()
  noctalia.runAsync("hyprctl dispatch 'hl.plugin.hyprdictate.toggle()'")
end

function onRightClick()
  noctalia.runAsync("hyprctl dispatch 'hl.plugin.hyprdictate.cancel()'")
end
