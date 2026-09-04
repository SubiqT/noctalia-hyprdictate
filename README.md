# noctalia-hyprdictate

[Noctalia](https://noctalia.dev) bar widget for the
[hyprdictate](https://github.com/SubiqT/hyprdictate) voice dictation
daemon and its Hyprland compositor plugin. Keeps a compact state glyph in the
bar and opens an attached, wrapped Moonshine transcript panel while you speak.

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
- **Live transcript panel**: opens automatically when recording begins,
  including sessions started with `Super+H`. Partial hypotheses wrap inside an
  attached scrollable panel and preserve newlines. Transcript text never
  renders inline, so bar spacing stays stable. Only Moonshine's finalized
  result is injected into the target application.
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
| `show_state_text` | `bool` | `false` | Show the state name next to the glyph. The transcript always remains in the panel. |

The transcript panel requests 520×132 logical pixels; on Noctalia 5.0.1 its
attached layer surface measures approximately 572×148 including host chrome—
exactly half the previous 296px surface height. The root fills that area and
allocates the remaining height to a 3–4 line wrapped scroll viewport.

For NixOS integration, filter the exact `^hyprdictate$` PipeWire node identity
via `shell.privacy.mic_filter_regex`. Noctalia applies that filter to both its
privacy OSD and privacy bar indicator; hyprdictate's own bar glyph and panel
provide the recording indication instead, while other capture apps still use
Noctalia's privacy UI.

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

At load, the bar entry opens `$XDG_RUNTIME_DIR/hyprdictate.sock` through a
reconnecting `nc -U` loop and consumes the daemon's line-delimited JSON:

- `{"event":"state","value":"recording"}` updates the glyph and opens the panel.
- `{"event":"transcript","text":"…","final":false}` replaces the panel buffer.
- `{"event":"transcript","text":"…","final":true}` records the finalized transcript.

The bar and panel run in separate Luau runtimes. The bar publishes each snapshot
through `noctalia.state`; `preview.luau` watches that state and re-renders a
scrollable unlimited-line label. On Idle, Cancelled, or Error it closes itself.
Click actions call `hyprctl` with `hl.plugin.hyprdictate.<action>()`; the
compositor plugin captures the target window and injects only finalized text.

## Non-goals

- Cross-compositor actions. Preview events come directly from the daemon, but
  start/cancel and deterministic final injection still use the Hyprland plugin.
- Transcript history. The live and last-finalized previews are held only in
  memory for the current widget process; nothing is persisted.

## Licence

MIT. See [LICENSE](LICENSE).
