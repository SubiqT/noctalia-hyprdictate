# noctalia-hyprdictate

[Noctalia](https://noctalia.dev) bar widget for the
[hyprdictate](https://github.com/SubiqT/hyprdictate) voice dictation
daemon and its Hyprland compositor plugin. Shows dictation state
(idle / recording / transcribing / error), lets you toggle with a
left click and cancel with a right click.

## Behaviour

- **Live waveform during recording**: a rolling ~2 s audio-level
  graph is drawn inline in the widget, driven by 20 Hz Level events
  from the daemon. Immediate visual confirmation that the mic is
  hearing you.
- **Pill for other states**: idle shows a `microphone` glyph with
  no fill (blends with the bar); transcribing / error / cancelled
  wrap a state glyph in a subtly tinted rounded pill (`dots`,
  `alert-triangle`, `player-stop`).
- **Colour**: follows the Noctalia palette — `primary` (idle),
  `error` (recording, error), `secondary` (transcribing), or
  `outline` (cancelled). All fills use fractional-alpha palette
  roles so theme changes retint the widget automatically.
- **Left click**: `hl.plugin.hyprdictate.toggle()` on the
  compositor plugin. Starts / stops dictation. Because the
  dispatcher lives in the compositor plugin, the plugin captures
  the focused window on the Recording edge and injects into that
  same window when the transcript arrives.
- **Right click**: `hl.plugin.hyprdictate.cancel()`. Discards any
  in-flight recording.
- **Hover tooltip**: `hyprdictate: <state> · left click to toggle,
  right click to cancel`.

The widget subscribes directly to the daemon's unix socket
(`$XDG_RUNTIME_DIR/hyprdictate.sock`) via a long-lived `nc -U`
pipe, so it sees the full JSON event stream — state, level, and
(in a future release) transcript. This decouples the widget from
Hyprland's socket2 and means the widget renders correctly on any
compositor as long as the daemon is running, though click actions
still require the Hyprland-plugin path for deterministic-target
injection.

If the daemon isn't running, or `nc` is missing, the widget stays
visible with the idle glyph but never updates. It never emits an
error toast — mirroring the design of the sibling
`noctalia-hyprwsmode` widget.

## Requirements

- **Hyprland 0.55+**.
- The [hyprdictate](https://github.com/SubiqT/hyprdictate) daemon
  and compositor plugin, both loaded and running.
- **Noctalia v5**.
- `nc` on `$PATH` supporting `-U` for Unix-domain sockets. Standard
  on NixOS (via libressl), Arch (`openbsd-netcat`), Debian
  (`netcat-openbsd`), and Fedora (`nmap-ncat`). GNU netcat lacks
  `-U` and will not work.

## Install

### Nix flakes (recommended for NixOS)

Follow the compositor and shell inputs so everything shares one
nixpkgs / Hyprland pair:

```nix
{
  inputs = {
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";

    hyprdictate = {
      url = "github:SubiqT/hyprdictate";
      inputs.hyprland.follows = "hyprland";
    };

    noctalia-hyprdictate = {
      url = "github:SubiqT/noctalia-hyprdictate";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

Load the daemon + plugin per the
[hyprdictate](https://github.com/SubiqT/hyprdictate) README, then
expose the widget to Noctalia as a `path` source and enable it:

```nix
{
  plugins.enabled = [ "subiqt/hyprdictate" ];
  plugins.source = [
    {
      name     = "subiqt-hyprdictate";
      kind     = "path";
      location = "${inputs.noctalia-hyprdictate.packages.${pkgs.system}.default}";
    }
  ];
}
```

`nixos-rebuild switch` deploys it. To bump, run `nix flake update
noctalia-hyprdictate` (or plain `nix flake update`) then rebuild.

The flake supports `x86_64-linux` and `aarch64-linux`.

### Manual (non-Nix)

Install the [hyprdictate](https://github.com/SubiqT/hyprdictate)
daemon and compositor plugin per its README, then:

```sh
noctalia msg plugins source add subiqt-hyprdictate git https://github.com/SubiqT/noctalia-hyprdictate
noctalia msg plugins enable subiqt/hyprdictate
```

Bump with `noctalia msg plugins update subiqt-hyprdictate`.

## Placing the widget

Once enabled, the widget appears as **Hyprdictate** in Noctalia's
Add-widget picker. To wire it explicitly in TOML:

```toml
[widget.hyprdictate]
type = "subiqt/hyprdictate:hyprdictate"
```

## Configuration

Per-widget settings, edited alongside the widget in Noctalia's bar
configuration:

| Setting                     | Type   | Default | Description                                                                                              |
| ---                         | ---    | ---     | ---                                                                                                      |
| `show_state_text`           | `bool` | `false` | Show the state name (Idle, Recording, Transcribing, …) next to the glyph.                                |
| `transcript_preview_length` | `int`  | `60`    | Reserved. Max chars of the last transcript to show on hover; wired up when the transcript cache lands.   |

Colours follow Noctalia's palette roles so they track theme
changes automatically.

## Development

Point Noctalia at a working checkout for hot-reloading Luau edits:

```sh
noctalia msg plugins source add hyprdictate-dev path ~/dev/noctalia-hyprdictate
noctalia msg plugins enable subiqt/hyprdictate
```

`.luau` edits hot-reload on save. Manifest (`plugin.toml`) changes
are picked up on the next config reload.

## How it works

At load, the widget resolves `$XDG_RUNTIME_DIR` and opens a single
`nc -U $XDG_RUNTIME_DIR/hyprdictate.sock` stream via
`noctalia.runStream`. The daemon writes newline-delimited JSON, one
envelope per line:

- `{"event":"state","value":"..."}` — daemon state transition. The
  widget mirrors it into its render tree, clearing the rolling
  level buffer on the Recording edge.
- `{"event":"level","value":0.42}` — normalised audio envelope on
  a dB-mapped 0..1 scale, emitted at 20 Hz while state is
  Recording. The widget appends to a 40-point rolling window and
  re-renders through `barWidget.render` so `ui.graph` shows the
  live waveform.
- `{"event":"transcript","text":"..."}` and `{"event":"error",...}`
  are ignored today; transcript preview lands with the M4
  transcript cache.

Whenever state or level changes the widget re-renders. There is no
`setUpdateInterval` and no polling; the socket is the sole update
trigger. Click actions call `hyprctl dispatch
'hl.plugin.hyprdictate.<action>()'` and let the compositor plugin
decide the next state, which returns through the same stream — no
optimistic UI mutation.

## Non-goals

- Cross-compositor support. Hyprland-only, since the widget relies
  on the hyprdictate compositor plugin's dispatchers and Hyprland's
  socket2.
- Transcript history. The widget receives transcripts (in a future
  hyprdictate release) only for tooltip preview; nothing persists.

## Licence

MIT. See [LICENSE](LICENSE).
