--!nonstrict

-- Bar widget for the hyprdictate voice dictation stack (daemon +
-- Hyprland compositor plugin).
--
-- The widget subscribes to the daemon's unix-socket event stream at
-- $XDG_RUNTIME_DIR/hyprdictate.sock via a long-lived `nc -U` pipe.
-- Every line is a JSON envelope from the wire protocol:
--
--   {"event":"state","value":"recording"}
--   {"event":"level","value":0.42}
--   {"event":"transcript","text":"..."}
--   {"event":"error","message":"..."}
--
-- Subscribing to the daemon socket directly (rather than via the
-- compositor plugin's socket2 emission) gives the widget access to
-- the full event stream — including the ~20 Hz Level meter used to
-- draw the live waveform below — and decouples read-side rendering
-- from whether the plugin happens to be loaded. Click actions still
-- route through the plugin's Hyprland dispatchers because those
-- capture the focused window for deterministic-target injection
-- (see the click block at the bottom of the file).
--
-- Rendering uses Noctalia's declarative barWidget.render() so the
-- widget can present as either:
--
--   * A live audio-level graph (ui.graph) while Recording, giving
--     the user immediate visual confirmation that their voice is
--     being captured.
--   * A subtle pill (glyph + optional label with a state-tinted
--     background) in every other state.
--
-- The pill's fill uses palette-role colours at fractional alpha so
-- theme changes retint it live. Idle stays fill-less so the widget
-- blends with other bar widgets when nothing is happening.
--
-- Graceful degradation: no error toasts anywhere. If the daemon is
-- not running (socket missing / connection refused), the `nc`
-- command exits and no events arrive; the widget stays in the idle
-- default. If `nc` is missing or lacks -U (GNU netcat), same path.

-- State → visual mapping for non-recording states. Recording gets a
-- custom rendering below rather than a static glyph.
--
-- `glyph`  — Tabler icon slug (Noctalia's default icon set).
-- `color`  — Noctalia palette role for the glyph and label.
-- `pill`   — palette role + fractional alpha for the subtle pill
--            fill; `false` means "no fill" (idle blends with the
--            bar). Alpha 0.18 is the sweet spot on both light and
--            dark themes: enough to read as a state pill, not
--            enough to fight surrounding widgets for attention.
local STATES = {
  idle = {
    glyph = "microphone",
    color = "primary",
    pill  = false,
  },
  transcribing = {
    glyph = "dots",
    color = "secondary",
    pill  = "secondary/0.18",
  },
  error = {
    glyph = "alert-triangle",
    color = "error",
    pill  = "error/0.18",
  },
  cancelled = {
    glyph = "player-stop",
    color = "outline",
    pill  = "outline/0.18",
  },
}

-- Display names for state values. Wire values are lowercase to
-- match the daemon's formatState output; the widget's user-facing
-- text capitalises for readability.
local DISPLAY_NAME = {
  idle         = "Idle",
  recording    = "Recording",
  transcribing = "Transcribing",
  error        = "Error",
  cancelled    = "Cancelled",
}

-- Rolling window of the last N level samples. Sized so the visible
-- graph shows roughly the past 2 seconds of audio — long enough to
-- read a rhythm, short enough to feel responsive. Daemon emits at
-- 20 Hz (50 ms per sample), so 40 points is 2.0 s of history.
local LEVEL_WINDOW = 40
local levels = {}

-- Prime with zeros so the first render draws a full-width flat line
-- rather than starting empty on the left and filling in. Reads more
-- polished than a sudden bar-materialisation on the first sample.
for _ = 1, LEVEL_WINDOW do
  levels[#levels + 1] = 0
end

local function pushLevel(v)
  levels[#levels + 1] = v
  if #levels > LEVEL_WINDOW then
    table.remove(levels, 1)
  end
end

local function resetLevels()
  levels = {}
  for _ = 1, LEVEL_WINDOW do
    levels[#levels + 1] = 0
  end
end

-- Settings read once at load. Noctalia rebuilds the widget entry on
-- any settings change, so caching in locals is safe and cheaper than
-- a noctalia.getConfig call per render.
local showStateText = noctalia.getConfig("show_state_text")

-- Reserved for M4 (transcript preview in tooltip). Parsed now so
-- the wire between the manifest and the runtime is exercised from
-- day one.
local _transcriptPreviewLength = noctalia.getConfig("transcript_preview_length")

-- Default to Idle. See the bootstrap comment further down for the
-- "starts mid-recording" caveat.
local currentState = "idle"

-- Build the ui.* tree for a non-recording state.
local function pillTree(state)
  local s       = STATES[state] or STATES.idle
  local display = DISPLAY_NAME[state] or state

  local children = {
    ui.glyph({ name = s.glyph, color = s.color }),
  }

  if showStateText then
    table.insert(children, ui.label({
      text       = display,
      color      = s.color,
      fontWeight = "medium",
    }))
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  return container({
    gap      = 6,
    align    = "center",
    paddingH = 8,
    paddingV = 2,
    radius   = 12,
    fill     = s.pill or nil,
  }, children)
end

-- Build the ui.* tree for the Recording state: live level graph in
-- an error-tinted pill, matching the palette hint that recording is
-- an active/attention state.
local function waveformTree()
  local children = {
    ui.graph({
      values      = levels,
      color       = "error",
      lineWidth   = 1.5,
      fillOpacity = 0.35,
      width       = 60,
    }),
  }

  if showStateText then
    table.insert(children, ui.label({
      text       = "Recording",
      color      = "error",
      fontWeight = "medium",
    }))
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  return container({
    gap      = 6,
    align    = "center",
    paddingH = 8,
    paddingV = 2,
    radius   = 12,
    fill     = "error/0.18",
  }, children)
end

local function render()
  local display = DISPLAY_NAME[currentState] or currentState

  -- Single-line tooltip with a discoverability hint. Noctalia
  -- tooltips render inline in the bar's tooltip panel, so keeping
  -- it short avoids awkward line wrapping.
  barWidget.setTooltip(
    "hyprdictate: " .. display ..
    " · left click to toggle, right click to cancel"
  )

  if currentState == "recording" then
    barWidget.render(waveformTree())
  else
    barWidget.render(pillTree(currentState))
  end

  barWidget.setVisible(true)
end

-- ── daemon-socket line parser ──────────────────────────────────────

local function onLine(line)
  -- Cheap prefix check before the full JSON decode: nc can also
  -- emit stderr lines / connection banners that never look like our
  -- events. Skipping non-object payloads early avoids surprising
  -- json.decode errors from filling the Noctalia log.
  if type(line) ~= "string" or line == "" then return end
  if line:sub(1, 1) ~= "{" then return end

  local ev = noctalia.json.decode(line)
  if type(ev) ~= "table" or type(ev.event) ~= "string" then return end

  if ev.event == "state" then
    local value = ev.value
    if type(value) ~= "string" then return end
    if currentState == value then return end
    -- Clear the rolling levels on every state edge so a new
    -- recording starts from a clean flat line rather than the tail
    -- of the previous take.
    if value == "recording" or currentState == "recording" then
      resetLevels()
    end
    currentState = value
    render()
    return
  end

  if ev.event == "level" then
    if currentState ~= "recording" then return end
    local v = tonumber(ev.value) or 0
    -- Clamp on the widget side too; the daemon already clamps but
    -- a rogue producer shouldn't be able to spike the graph.
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    pushLevel(v)
    render()
    return
  end

  -- transcript / error / status events are ignored today. Transcript
  -- preview lands in M4 (see the transcript_preview_length setting);
  -- error is surfaced through the state=error path.
end

-- ── Bootstrap: connect to the daemon socket ────────────────────────

local xdgRuntime = noctalia.getenv("XDG_RUNTIME_DIR")
if xdgRuntime == nil or xdgRuntime == "" then
  -- No XDG_RUNTIME_DIR means Noctalia is running outside a normal
  -- session; skip the subscription and render the static idle pill.
  render()
else
  local socketPath = xdgRuntime .. "/hyprdictate.sock"
  -- OpenBSD-style netcat is required for -U (Unix-domain) support.
  -- runStream terminates the process automatically on script reload
  -- or entry removal. The daemon accepts anonymous subscribers, so
  -- no identify handshake is sent; the daemon's gating of wtype vs
  -- plugin-owned injection is unaffected by widget subscriptions.
  noctalia.runStream("nc -U '" .. socketPath .. "'", onLine)
  render()
end

-- ── Click actions ─────────────────────────────────────────────────
--
-- Route through the compositor plugin's dispatchers (registered as
-- hyprdictate:toggle / hyprdictate:cancel) rather than the daemon
-- CLI. The plugin captures the focused window on the Recording edge
-- and injects into that window when the transcript arrives; sending
-- the command straight to the daemon would give up that
-- deterministic-target property.
--
-- Failures (plugin not loaded, hyprctl missing) are silent — hyprctl
-- exits non-zero and the widget stays where it is. State transitions
-- always land back through onLine above, so the widget's next render
-- reflects the actual daemon state rather than an optimistic guess.

function onClick()
  noctalia.runAsync("hyprctl dispatch 'hl.plugin.hyprdictate.toggle()'")
end

function onRightClick()
  noctalia.runAsync("hyprctl dispatch 'hl.plugin.hyprdictate.cancel()'")
end

-- onMiddleClick is reserved for reload once the daemon exposes it
-- (M4 in the hyprdictate roadmap). Left unimplemented today so a
-- stray middle-click doesn't fire hyprctl for a dispatcher that
-- doesn't exist yet.
-- function onMiddleClick()
--   noctalia.runAsync("hyprdictate reload")
-- end
