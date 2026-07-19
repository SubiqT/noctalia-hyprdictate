--!nonstrict

-- Bar widget for the hyprdictate voice dictation stack (daemon +
-- Hyprland compositor plugin).
--
-- Subscribes to Hyprland's socket2 stream via a long-lived nc
-- process and filters the single prefix the compositor plugin
-- emits:
--
--   hyprdictate>>state,<idle|recording|transcribing|error|cancelled>
--
-- Every state transition delivered by the plugin updates the glyph,
-- glyph colour, and tooltip. Redundant emits are already suppressed
-- upstream (the plugin dedups against prev-state), so no widget-side
-- filtering is needed.
--
-- Bootstrap at load time:
--   1. `hyprctl instances -j`  discover the current session
--      signature so we can build the socket2 path even when
--      HYPRLAND_INSTANCE_SIGNATURE is not in Noctalia's env.
--   2. Start `nc -U .../.socket2.sock` via runStream. The compositor
--      plugin does not re-broadcast state on connect (it only emits
--      on transitions), so the widget defaults to "idle" and picks
--      up the real state on the next actual transition. In the
--      normal case (widget rebuilt / Noctalia reload while the
--      daemon is idle) this is invisible; the rare case of reloading
--      mid-recording briefly shows idle before the next state event.
--
-- Graceful degradation: no error toasts anywhere. If the compositor
-- plugin is not loaded, `hyprdictate>>` lines never arrive; the
-- widget stays in the idle default. If `nc` is missing or lacks -U
-- (GNU netcat), the shell command exits and the same non-render
-- path applies.

-- State → visual mapping, per hyprdictate's design doc:
--
--   idle          microphone            primary
--   recording     player-record-filled  error
--   transcribing  dots                  secondary
--   error         alert-triangle        error
--   cancelled     player-stop           outline   (transient; the
--                                                  plugin emits
--                                                  Idle immediately
--                                                  after, so this
--                                                  reads as a brief
--                                                  flash)
--
-- Glyph slugs are Tabler icon names (Noctalia's default icon set).
-- Palette roles are Noctalia palette identifiers; changing the
-- shell theme retints the widget automatically because the widget
-- refers to roles rather than hex.
local STATES = {
  idle = {
    glyph = "microphone",
    color = "primary",
  },
  recording = {
    glyph = "player-record-filled",
    color = "error",
  },
  transcribing = {
    glyph = "dots",
    color = "secondary",
  },
  error = {
    glyph = "alert-triangle",
    color = "error",
  },
  cancelled = {
    glyph = "player-stop",
    color = "outline",
  },
}

-- Settings read once at load. Noctalia rebuilds the widget entry on
-- any settings change, so caching in locals is safe and cheaper than
-- a noctalia.getConfig call per render.
local showStateText = noctalia.getConfig("show_state_text")

-- Reserved for M4 (transcript preview in tooltip). Parsed now so
-- the wire between the manifest and the runtime is exercised from
-- day one.
local _transcriptPreviewLength = noctalia.getConfig("transcript_preview_length")

-- Default to Idle. See the bootstrap comment at the top of the file
-- for the "starts mid-recording" caveat.
local currentState = "idle"

local function render()
  local s = STATES[currentState] or STATES.idle
  barWidget.setGlyph(s.glyph)
  barWidget.setGlyphColor(s.color)
  barWidget.setText(showStateText and currentState or "")
  barWidget.setTooltip("hyprdictate: " .. currentState)
  barWidget.setVisible(true)
end

-- ── socket2 line parser ────────────────────────────────────────────

local function onLine(line)
  -- hyprdictate>>state,<value>. Match one of the five known state
  -- names to avoid tripping on a malformed line or a future value
  -- this widget doesn't understand.
  local value = line:match("^hyprdictate>>state,(%a+)")
  if value == nil then return end
  if STATES[value] == nil then return end
  currentState = value
  render()
end

-- ── Bootstrap: discover the Hyprland instance, then start the stream

noctalia.runAsync("hyprctl instances -j", function(res)
  if res.exitCode ~= 0 then return end
  local instances = noctalia.json.decode(res.stdout)
  if type(instances) ~= "table" or #instances == 0 then return end
  local sig = instances[1].instance
  if type(sig) ~= "string" or sig == "" then return end

  local xdgRuntime = noctalia.getenv("XDG_RUNTIME_DIR")
  if xdgRuntime == nil or xdgRuntime == "" then return end
  local socketPath = xdgRuntime .. "/hypr/" .. sig .. "/.socket2.sock"

  -- nc streams the socket line-by-line to stdout. OpenBSD-style
  -- netcat is required for -U (Unix-domain) support. runStream
  -- terminates the process automatically on script reload / entry
  -- removal.
  noctalia.runStream("nc -U '" .. socketPath .. "'", onLine)
end)

-- Initial render with the default idle glyph. Fires before the
-- socket2 stream is up so the bar has something visible even in
-- the tiny bootstrap window.
render()
