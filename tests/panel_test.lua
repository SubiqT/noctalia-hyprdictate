local rendered = nil
local closed = 0
local watchCallback = nil
local current = {
  state = "recording",
  preview = "first line\nsecond line",
  final = "",
  revision = 1,
}

local function ctor(kind)
  return function(props, children)
    return { type = kind, props = props or {}, children = children or {} }
  end
end

ui = {
  column = ctor("column"),
  row = ctor("row"),
  glyph = ctor("glyph"),
  label = ctor("label"),
  scroll = ctor("scroll"),
}

noctalia = {
  tr = function(key)
    local values = {
      ["panel.title"] = "Live transcript",
      ["panel.listening"] = "Listening…",
      ["panel.finalizing"] = "Finalizing transcript…",
      ["panel.empty"] = "No speech detected yet.",
    }
    return values[key] or key
  end,
  state = {
    get = function(key)
      assert(key == "dictation")
      return current
    end,
    watch = function(key, callback)
      assert(key == "dictation")
      watchCallback = callback
    end,
  },
}

panel = {
  render = function(tree) rendered = tree end,
  close = function() closed = closed + 1 end,
}

assert(loadfile("hyprdictate/preview.luau"))()
assert(watchCallback ~= nil, "panel must watch shared dictation state")
assert(rendered ~= nil and rendered.type == "column", "panel renders a root column")
assert(rendered.props.flexGrow == 1, "root fills the panel instead of leaving blank space")
assert(rendered.props.padding == 12 and rendered.props.gap == 8,
       "compact panel uses measured padding")
assert(closed == 0, "recording panel remains open")

local scroll = rendered.children[2]
assert(scroll.type == "scroll" and scroll.props.flexGrow == 1,
       "transcript uses a growing scroll viewport")
assert(scroll.props.padding == 8 and scroll.props.radius == 8,
       "scroll viewport uses compact measured insets")
assert(scroll.props.stickToBottom == true, "latest transcript remains visible")
local transcript = scroll.children[1]
assert(transcript.type == "label", "transcript renders as a label")
assert(transcript.props.text == "first line\nsecond line", "newlines are preserved")
assert(transcript.props.maxWidth == 480, "label uses the measured inner wrapping width")
assert(transcript.props.maxLines == 0, "label has no line truncation")

local longText = string.rep("wrapped words ", 60) .. "\nnew paragraph"
watchCallback({
  state = "transcribing",
  preview = longText,
  final = "",
  revision = 2,
})
scroll = rendered.children[2]
transcript = scroll.children[1]
assert(transcript.props.text == longText, "long updates are never truncated")
assert(scroll.props.scrollToBottomRev == 2, "updates advance scroll revision")
assert(closed == 0, "transcribing panel remains open")

watchCallback({ state = "idle", preview = "", final = "done", revision = 3 })
assert(closed == 1, "panel closes when dictation returns idle")

closed = 0
watchCallback({ state = "cancelled", preview = "", final = "", revision = 4 })
assert(closed == 1, "panel closes when dictation is cancelled")

closed = 0
watchCallback({ state = "error", preview = "", final = "", revision = 5 })
assert(closed == 1, "panel closes when dictation errors")
