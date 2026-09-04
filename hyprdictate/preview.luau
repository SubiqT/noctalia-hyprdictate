--!nonstrict

-- Attached transcript preview panel. The bar widget owns the daemon socket and
-- publishes snapshots through noctalia.state; this panel only renders them.

local STATE_KEY = "dictation"

local STATES = {
  idle = { glyph = "microphone", color = "primary", name = "Idle" },
  recording = { glyph = "player-record-filled", color = "error", name = "Recording" },
  transcribing = { glyph = "dots", color = "secondary", name = "Transcribing" },
  error = { glyph = "alert-triangle", color = "error", name = "Error" },
  cancelled = { glyph = "player-stop", color = "outline", name = "Cancelled" },
}

local snapshot = {
  state = "idle",
  preview = "",
  final = "",
  revision = 0,
}

local function transcriptText()
  if snapshot.preview ~= nil and snapshot.preview ~= "" then
    return snapshot.preview
  end
  if snapshot.state == "recording" then
    return noctalia.tr("panel.listening")
  end
  if snapshot.state == "transcribing" then
    return noctalia.tr("panel.finalizing")
  end
  if snapshot.final ~= nil and snapshot.final ~= "" then
    return snapshot.final
  end
  return noctalia.tr("panel.empty")
end

local function render()
  local state = STATES[snapshot.state] or STATES.idle
  local revision = tonumber(snapshot.revision) or 0

  panel.render(ui.column({
    padding = 16,
    gap = 12,
  }, {
    ui.row({
      gap = 10,
      align = "center",
    }, {
      ui.glyph({
        name = state.glyph,
        size = 18,
        color = state.color,
      }),
      ui.label({
        text = noctalia.tr("panel.title"),
        color = "on_surface",
        fontWeight = "bold",
        flexGrow = 1,
      }),
      ui.label({
        text = state.name,
        color = state.color,
        fontSize = 12,
      }),
    }),
    ui.scroll({
      flexGrow = 1,
      padding = 12,
      fill = "surface_container",
      radius = 10,
      stickToBottom = true,
      scrollToBottomRev = revision,
    }, {
      ui.label({
        key = "transcript",
        text = transcriptText(),
        color = "on_surface",
        maxWidth = 456,
        maxLines = 0,
        textAlign = "start",
      }),
    }),
  }))
end

local function apply(nextSnapshot)
  if type(nextSnapshot) ~= "table" then return end
  snapshot = nextSnapshot
  render()

  if snapshot.state == "idle" or snapshot.state == "cancelled"
      or snapshot.state == "error" then
    panel.close()
  end
end

noctalia.state.watch(STATE_KEY, apply)
local initial = noctalia.state.get(STATE_KEY)
if type(initial) == "table" then snapshot = initial end
render()
