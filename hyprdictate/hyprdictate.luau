--!nonstrict

-- Bar widget for the hyprdictate voice dictation stack (daemon +
-- Hyprland compositor plugin).
--
-- M3.1: static "idle" render. The widget shows a microphone glyph
-- and, if the user enables show_state_text, the literal label
-- "idle". No socket subscription, no click handlers yet — those
-- land in M3.2 and M3.3 respectively.
--
-- Rationale for staging the milestones this way: pushing a static
-- widget first lets us verify the Nix packaging, the manifest, and
-- Noctalia's plugin scan against the user's config in isolation
-- from the socket-subscription plumbing. If anything is wrong with
-- the wiring (plugin id, entry path, min_noctalia), it surfaces on
-- M3.1 rather than mixed with a socket-subscription bug in M3.2.

-- Settings read once at load. Noctalia rebuilds the widget entry
-- on any settings change, so caching in locals is safe and cheaper
-- than a noctalia.getConfig call per render.
local showStateText = noctalia.getConfig("show_state_text")

-- Reserved for M4 (transcript preview in tooltip). Parsed now so
-- the wire between the manifest and the runtime is exercised from
-- day one.
local _transcriptPreviewLength = noctalia.getConfig("transcript_preview_length")

local function render()
  -- Tabler icon name; matches hyprwsmode's convention of picking
  -- glyphs by Tabler slug rather than raw unicode.
  barWidget.setGlyph("microphone")
  barWidget.setText(showStateText and "idle" or "")
  barWidget.setTooltip("hyprdictate: idle")
  barWidget.setVisible(true)
end

render()
