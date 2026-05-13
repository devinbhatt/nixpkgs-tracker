{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (import ./fixtures.nix { inherit pkgs; }) fakeCurl;

      # All fixture-backed entries. Each (url, description) combo exercises
      # one branch in check.sh.
      fixtureEntries = [
        {
          url = "github:NixOS/nixpkgs/pull/900001";
          description = "nixpkgs-pr-shipped";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          # Same fixture, but spelled `pulls/` — exercises the parser branch.
          url = "github:NixOS/nixpkgs/pulls/900001";
          description = "nixpkgs-pr-plural-url";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "github:NixOS/nixpkgs/pull/900002";
          description = "nixpkgs-pr-not-shipped";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "github:NixOS/nixpkgs/pull/900003";
          description = "nixpkgs-pr-open";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "github:NixOS/nixpkgs/pull/900004";
          description = "nixpkgs-pr-closed-unmerged";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "github:NixOS/nixpkgs/pull/900005";
          description = "nixpkgs-pr-cherrypick";
          message = null;
          targetChannel = "staging-next";
        }
        {
          url = "github:NixOS/nixpkgs/pull/900006";
          description = "nixpkgs-pr-stale";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "github:NixOS/nixpkgs/pull/900007";
          description = "nixpkgs-pr-no-sha";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "github:NixOS/nixpkgs/issues/900010";
          description = "nixpkgs-issue-closed";
          message = "drop the patch";
          targetChannel = "nixos-unstable";
        }
        {
          url = "github:NixOS/nixpkgs/issues/900011";
          description = "nixpkgs-issue-linked-pr";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "github:NixOS/nixpkgs/issues/900012";
          description = "nixpkgs-issue-open-silent";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "https://github.com/octocat/widget/pull/900020";
          description = "external-pr-merged";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "github:octocat/widget/pull/900021";
          description = "external-pr-open";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "github:octocat/widget/issues/900022";
          description = "external-issue-closed";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "github:octocat/widget/issues/900023";
          description = "external-issue-open";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "github:octocat/widget/pull/900024";
          description = "external-pr-stale";
          message = null;
          targetChannel = "nixos-unstable";
        }
        {
          url = "https://github.com/owner/repo";
          description = "bad-url-entry";
          message = null;
          targetChannel = "nixos-unstable";
        }
      ];

      # Build the check with `curl` replaced by the fixture wrapper. The
      # script's own PATH manipulation can no longer reach the real curl.
      fixtureCheck = import ../packages/check.nix {
        pkgs = pkgs // {
          curl = fakeCurl;
        };
        entries = fixtureEntries;
        timeoutSeconds = 1;
        failOpen = false;
      };

      # Lines that MUST appear in the combined output.
      expectations = [
        "nixpkgs-pr-shipped: PR #900001 has reached nixos-unstable"
        "nixpkgs-pr-plural-url: PR #900001 has reached nixos-unstable"
        "nixpkgs-pr-cherrypick: PR #900005 has reached staging-next"
        "nixpkgs-pr-closed-unmerged: PR #900004 was closed without merging"
        "nixpkgs-pr-stale: PR #900006 is marked stale"
        "nixpkgs-pr-no-sha: PR #900007 merged but no merge_commit_sha"
        "nixpkgs-issue-closed: issue #900010 is closed. drop the patch"
        "nixpkgs-issue-linked-pr: issue #900011 now has linked PR #900099"
        "external-pr-merged: upstream octocat/widget PR #900020 is merged"
        "external-issue-closed: upstream octocat/widget issue #900022 is closed"
        "external-pr-stale: upstream octocat/widget PR #900024 is marked stale"
        "skipping unparseable url: https://github.com/owner/repo"
      ];

      # Substrings that MUST NOT appear (silent paths + fixture sanity).
      forbidden = [
        "nixpkgs-pr-not-shipped"
        "nixpkgs-pr-open:"
        "nixpkgs-issue-open-silent"
        "external-pr-open:"
        "external-issue-open"
        "FIXTURE MISS"
      ];

    in
    {
      checks.eval-module =
        let
          mkModule = import ../modules/system.nix { defaultTargetChannel = "test-channel"; };
          eval = lib.evalModules {
            modules = [
              { _module.args = { inherit pkgs; }; }
              {
                options.system.activationScripts = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = { };
                };
              }
              mkModule
              {
                nixpkgs-tracker.entries = [
                  {
                    url = "github:NixOS/nixpkgs/pull/123456";
                    description = "default-channel-inherits";
                  }
                  {
                    url = "github:NixOS/nixpkgs/pull/123457";
                    description = "per-entry-override";
                    targetChannel = "nixos-25.05";
                  }
                ];
              }
            ];
          };
          activationText = eval.config.system.activationScripts.nixpkgs-tracker.text;
          # The activation text references the built check binary; pull the
          # store path out so we can read its source.
          checkBin = lib.head (
            builtins.match ".*(/nix/store/[a-z0-9]+-nixpkgs-tracker-check)/bin/.*" activationText
          );
        in
        pkgs.runCommand "nixpkgs-tracker-eval"
          {
            inherit activationText;
            checkScript = "${checkBin}/bin/nixpkgs-tracker-check";
          }
          ''
            # 1. Activation snippet points at a check binary.
            printf '%s' "$activationText" | grep -q 'nixpkgs-tracker-check' || {
              echo "activation text does not reference check binary" >&2
              exit 1
            }
            # 2. Entries that didn't set targetChannel inherit defaultTargetChannel;
            #    per-entry overrides win.
            grep -q '"targetChannel":"test-channel"' "$checkScript" || {
              echo "expected default channel 'test-channel' in entries JSON" >&2
              exit 1
            }
            grep -q '"targetChannel":"nixos-25.05"' "$checkScript" || {
              echo "expected per-entry override 'nixos-25.05' in entries JSON" >&2
              exit 1
            }
            touch $out
          '';

      checks.fixture-test =
        pkgs.runCommand "nixpkgs-tracker-fixture-test"
          {
            nativeBuildInputs = with pkgs; [
              jq
              coreutils
            ];
          }
          ''
            set -euo pipefail
            export PATH="${fakeCurl}/bin:$PATH"

            # Sanity: confirm we're seeing the fake curl.
            curl_path=$(command -v curl)
            case $curl_path in
              ${fakeCurl}/bin/*) ;;
              *) echo "fake curl not first in PATH: $curl_path" >&2; exit 1 ;;
            esac

            captured=$(${lib.getExe fixtureCheck} 2>&1 || true)
            printf '=== check output ===\n%s\n=== end ===\n' "$captured"

            fail=0
            ${lib.concatMapStringsSep "\n" (e: ''
              grep -qF ${lib.escapeShellArg e} <<<"$captured" || {
                echo "MISSING expected line: ${e}" >&2
                fail=1
              }
            '') expectations}
            ${lib.concatMapStringsSep "\n" (f: ''
              if grep -qF ${lib.escapeShellArg f} <<<"$captured"; then
                echo "UNEXPECTED line containing: ${f}" >&2
                fail=1
              fi
            '') forbidden}

            if [[ $fail -eq 0 ]]; then
              touch $out
            else
              exit "$fail"
            fi
          '';

      # Live API test — `nix run .#test-live`. Hits real GitHub against
      # stable long-merged/long-closed targets. Not part of `flake check`
      # (Nix builds have no network); meant for catching API drift manually.
      apps.test-live = {
        type = "app";
        program = lib.getExe (
          import ../packages/check.nix {
            inherit pkgs;
            timeoutSeconds = 10;
            failOpen = false;
            entries = [
              {
                url = "github:NixOS/nixpkgs/pull/1";
                description = "live-nixpkgs-pr-ancient";
                message = null;
                targetChannel = "nixos-unstable";
              }
              {
                url = "github:NixOS/nixpkgs/issues/2";
                description = "live-nixpkgs-issue-ancient";
                message = null;
                targetChannel = "nixos-unstable";
              }
              {
                url = "github:octocat/Hello-World/pull/1";
                description = "live-external-pr";
                message = null;
                targetChannel = "nixos-unstable";
              }
              {
                url = "github:octocat/Hello-World/issues/1";
                description = "live-external-issue";
                message = null;
                targetChannel = "nixos-unstable";
              }
            ];
          }
        );
        meta.description = "Run the check against real GitHub URLs to catch API drift.";
      };
    };
}
