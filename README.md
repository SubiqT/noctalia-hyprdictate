# noctalia-hyprdictate

[Noctalia](https://noctalia.dev) bar widget for the
[hyprdictate](https://github.com/SubiqT/hyprdictate) voice dictation
daemon and its Hyprland compositor plugin. Shows dictation state
(idle / recording / transcribing / error) and lets you click to
toggle or cancel.

## Requirements

- **Hyprland 0.55+**.
- The [hyprdictate](https://github.com/SubiqT/hyprdictate) daemon
  and compositor plugin, both loaded and running.
- **Noctalia v5**.
- `nc` on `$PATH` supporting `-U` for Unix-domain sockets. Standard
  on NixOS (via libressl), Arch (`openbsd-netcat`), Debian
  (`netcat-openbsd`), and Fedora (`nmap-ncat`). GNU netcat lacks
  `-U` and will not work.

## Milestone status

Delivered as a series of small releases (see the roadmap in the
[hyprdictate design doc](https://github.com/SubiqT/hyprdictate)):

- **M3.1** (this release) — static widget. Renders a microphone
  glyph on the bar; verifies packaging and manifest scan.
- **M3.2** — subscribes to Hyprland's socket2 for
  `hyprdictate>>state,...` and updates glyph + colour per state.
- **M3.3** — click handlers: left toggles, right cancels.
- **M3.4** — settings + polish: `show_state_text`, tooltip content,
  glyph palette review.

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
expose the widget to Noctalia as a `path` source:

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

The flake supports `x86_64-linux` and `aarch64-linux`.

### Manual (non-Nix)

```sh
noctalia msg plugins source add subiqt-hyprdictate git https://github.com/SubiqT/noctalia-hyprdictate
noctalia msg plugins enable subiqt/hyprdictate
```

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
| `show_state_text`           | `bool` | `false` | Show the state name (idle, recording, transcribing) next to the glyph.                                   |
| `transcript_preview_length` | `int`  | `60`    | Reserved. Max chars of the last transcript to show on hover; wired up when the transcript cache lands.   |

## Licence

MIT. See [LICENSE](LICENSE).
