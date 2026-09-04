# noctalia-hyprdictate

[Noctalia](https://noctalia.dev) bar widget for the
[hyprdictate](https://github.com/SubiqT/hyprdictate) voice dictation
daemon and its Hyprland compositor plugin. Shows dictation state and a live,
replaceable Moonshine transcript while you speak, lets you toggle with a left
click, and cancels with a right click.

## Behaviour

- **Glyph**: `microphone`, `player-record-filled`, `dots`,
  `alert-triangle`, or `player-stop` depending on the daemon's
  current state.
- **Colour**: follows the Noctalia palette — `primary` (idle),
  `error` (recording, error), `secondary` (transcribing), or
  `outline` (cancelled). Theme changes retint the widget
  automatically.
- **Left click**: `hl.plugin.hyprdictate.toggle()` on the
  compositor plugin. Starts / stops dictation. Because the dispatcher lives in
  the compositor plugin, it captures the focused window on the Recording edge
  and injects into that same window when the final transcript arrives.
- **Live transcript**: while recording or finalizing, replaceable partial text
  appears beside the glyph and in the tooltip. Partial hypotheses are preview
  only; hyprdictate injects only Moonshine's finalized result. The last final
  transcript remains in the idle tooltip until the next recording starts.
- **Right click**: `hl.plugin.hyprdictate.cancel()`. Discards any
  in-flight recording.
- **Hover tooltip**: `hyprdictate: <state> · left click to toggle,
  right click to cancel`.

State and transcript previews are driven directly by the daemon's JSON socket
through a reconnecting `nc -U` stream. The widget idles at zero CPU between
events and reconnects automatically when the daemon restarts.

If the daemon or `nc` is unavailable, the widget stays visible with the idle
glyph and retries once a second. Click actions still require the compositor
plugin because it owns start-window capture and final text injection.

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
| `transcript_preview_length` | `int`  | `60`    | Maximum characters of the live or last finalized transcript shown in bar text and tooltip.                          |

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

At load, the widget opens `$XDG_RUNTIME_DIR/hyprdictate.sock` through a
reconnecting `nc -U` loop and consumes the daemon's line-delimited JSON:

- `{"event":"state","value":"recording"}` updates the state.
- `{"event":"transcript","text":"…","final":false}` replaces the live preview.
- `{"event":"transcript","text":"…","final":true}` records the finalized transcript.

Whenever an event arrives the widget re-renders; there is no polling interval.
Click actions call `hyprctl` with `hl.plugin.hyprdictate.<action>()` and let the
compositor plugin capture the target window and inject only finalized text.

## Non-goals

- Cross-compositor actions. Preview events come directly from the daemon, but
  start/cancel and deterministic final injection still use the Hyprland plugin.
- Transcript history. The live and last-finalized previews are held only in
  memory for the current widget process; nothing is persisted.

## Licence

MIT. See [LICENSE](LICENSE).
