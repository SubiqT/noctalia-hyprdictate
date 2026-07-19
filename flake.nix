{
  description = "Noctalia bar widget for the hyprdictate voice dictation stack";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      # NixOS + Hyprland + Noctalia audience is overwhelmingly on
      # these two systems; Hyprland itself only ships for these.
      # Keep in step with the sibling `noctalia-hyprwsmode` flake so
      # a consumer nix-config that picks up both widgets doesn't
      # trip a system-set divergence.
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = fn:
        nixpkgs.lib.genAttrs systems (system: fn nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        noctalia-hyprdictate = pkgs.callPackage ./default.nix { };
        default = noctalia-hyprdictate;
      });
    };
}
