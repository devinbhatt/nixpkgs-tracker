{ inputs, ... }:
let
  # When the consumer wires `inputs.nixpkgs-tracker.inputs.nixpkgs.follows =
  # "nixpkgs"`, `inputs.nixpkgs.original.ref` is their channel (e.g.
  # "nixos-unstable"). Fall back to our own input ref otherwise.
  defaultTargetChannel = inputs.nixpkgs.original.ref or "nixos-unstable";
  module = import ./system.nix { inherit defaultTargetChannel; };
in
{
  flake.nixosModules.default = module;
  flake.nixosModules.nixpkgs-tracker = module;
  flake.darwinModules.default = module;
  flake.darwinModules.nixpkgs-tracker = module;
}
