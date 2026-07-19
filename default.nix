{ lib, stdenvNoCC, nix-gitignore }:

# Static plugin bundle. No compilation needed: the plugin is a
# directory of Luau + TOML files that Noctalia loads at runtime.
# The derivation lays the repo's `hyprdictate/` subdirectory into
# `$out/hyprdictate/`, matching what a Noctalia `path` source expects
# to find (a directory containing one or more plugin subdirectories,
# each with a `plugin.toml`).
#
# Consumers:
#
#   inputs.noctalia-hyprdictate.url = "github:SubiqT/noctalia-hyprdictate";
#
#   # Then, in the Noctalia config file:
#   plugins = {
#     enabled = [ "subiqt/hyprdictate" ];
#     source = [{
#       name     = "subiqt-hyprdictate";
#       kind     = "path";
#       location = "${inputs.noctalia-hyprdictate.packages.${pkgs.system}.default}";
#     }];
#   };
stdenvNoCC.mkDerivation {
  pname = "noctalia-hyprdictate";
  version = "0.1.0";

  # nix-gitignore drops editor droppings and any local files matched
  # by .gitignore so the store path is the same bytes for the same
  # commit regardless of the developer's checkout state.
  src = nix-gitignore.gitignoreSource [ ] ./.;

  # No build. Copy the plugin directory verbatim so Noctalia's
  # source scan finds `hyprdictate/plugin.toml` at the expected
  # depth.
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r hyprdictate $out/
    runHook postInstall
  '';

  meta = with lib; {
    homepage    = "https://github.com/SubiqT/noctalia-hyprdictate";
    description = "Noctalia bar widget for the hyprdictate voice dictation stack";
    license     = licenses.mit;
    platforms   = platforms.linux;
  };
}
