{ defaultTargetChannel }:
{
  config,
  lib,
  pkgs,
  ...
}:
# Platform-neutral system module — works on both NixOS and nix-darwin, which
# expose `system.activationScripts.<name>.text` identically.
let
  cfg = config.nixpkgs-tracker;

  entryType = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.str;
        description = ''
          GitHub issue or PR. Accepts either
          `https://github.com/<owner>/<repo>/{issues,pull}/<n>` or the
          flake-style shorthand `github:<owner>/<repo>/{issues,pull}/<n>`.
        '';
        example = "github:NixOS/nixpkgs/pull/123456";
      };
      description = lib.mkOption {
        type = lib.types.str;
        description = "Short label shown in the warning banner.";
        example = "firefox crash-on-launch fix";
      };
      message = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Override for the action prompt (e.g. which overlay to remove).";
        example = "Remove the firefox overlay.";
      };
      targetChannel = lib.mkOption {
        type = lib.types.str;
        default = defaultTargetChannel;
        defaultText = lib.literalMD "the nixpkgs flake input ref";
        description = ''
          The nixpkgs branch this entry tracks. Defaults to your flake's
          nixpkgs input ref (e.g. `nixos-unstable`). Override per entry when
          you're cherry-picking from a different branch.
        '';
        example = "staging-next";
      };
    };
  };

  entries = map (e: {
    inherit (e)
      url
      description
      message
      targetChannel
      ;
  }) cfg.entries;

  check = import ../lib/mk-check.nix {
    inherit pkgs entries;
    inherit (cfg) timeoutSeconds failOpen;
  };
in
{
  options.nixpkgs-tracker = {
    enable = lib.mkEnableOption "nixpkgs-tracker activation-time GitHub status check" // {
      default = true;
    };

    entries = lib.mkOption {
      type = lib.types.listOf entryType;
      default = [ ];
      example = lib.literalExpression ''
        [
          {
            url = "github:NixOS/nixpkgs/pull/123456";
            description = "firefox crash-on-launch fix";
          }
          {
            url = "github:owner/project/issues/42";
            description = "upstream segfault on startup";
          }
        ]
      '';
      description = ''
        Issues/PRs to check on every system rebuild. Aggregated across all
        modules — declare entries next to the overlay they relate to.
      '';
    };

    timeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "Per-request curl timeout. Activation must not block long.";
    };

    failOpen = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When true, network failures (rate-limit, DNS) are silent. When false,
        each failure prints a diagnostic line. The rebuild never fails either way.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.entries != [ ]) {
    system.activationScripts.nixpkgs-tracker.text = ''
      ${lib.getExe check} || true
    '';
  };
}
