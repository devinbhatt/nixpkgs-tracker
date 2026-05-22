{ pkgs }:
let
  # Each fixture maps an api.github.com path → JSON body.
  # Placeholder PR/issue numbers (9000xx) so fake URLs can't collide with
  # anything real.
  fixtures = {
    # nixpkgs PR, merged + propagated to nixos-unstable
    "/repos/NixOS/nixpkgs/pulls/900001" = {
      state = "closed";
      merged = true;
      merge_commit_sha = "aaaa1111";
    };
    "/repos/NixOS/nixpkgs/compare/nixos-unstable...aaaa1111" = {
      status = "behind";
    };

    # nixpkgs PR, merged but NOT yet on nixos-unstable
    "/repos/NixOS/nixpkgs/pulls/900002" = {
      state = "closed";
      merged = true;
      merge_commit_sha = "bbbb2222";
    };
    "/repos/NixOS/nixpkgs/compare/nixos-unstable...bbbb2222" = {
      status = "diverged";
    };

    # nixpkgs PR, open
    "/repos/NixOS/nixpkgs/pulls/900003" = {
      state = "open";
      merged = false;
      merge_commit_sha = null;
    };

    # nixpkgs PR, closed without merging
    "/repos/NixOS/nixpkgs/pulls/900004" = {
      state = "closed";
      merged = false;
      merge_commit_sha = null;
    };

    # nixpkgs PR, propagated to a non-default channel (staging-next)
    "/repos/NixOS/nixpkgs/pulls/900005" = {
      state = "closed";
      merged = true;
      merge_commit_sha = "eeee5555";
    };
    "/repos/NixOS/nixpkgs/compare/staging-next...eeee5555" = {
      status = "identical";
    };

    # nixpkgs PR, open + carries a "stale"-ish label
    "/repos/NixOS/nixpkgs/pulls/900006" = {
      state = "open";
      merged = false;
      merge_commit_sha = null;
      labels = [
        { name = "10.rebuild-darwin: 0"; }
        { name = "2.status: stale"; }
      ];
    };

    # nixpkgs PR, merged but the API didn't give us a merge_commit_sha
    "/repos/NixOS/nixpkgs/pulls/900007" = {
      state = "closed";
      merged = true;
      merge_commit_sha = null;
    };

    # nixpkgs issue, closed
    "/repos/NixOS/nixpkgs/issues/900010" = {
      state = "closed";
    };

    # nixpkgs issue, open, with linked PR via timeline
    "/repos/NixOS/nixpkgs/issues/900011" = {
      state = "open";
    };
    "/repos/NixOS/nixpkgs/issues/900011/timeline?per_page=100" = [
      {
        event = "cross-referenced";
        source = {
          issue = {
            number = 900099;
            pull_request = {
              url = "https://api.github.com/repos/NixOS/nixpkgs/pulls/900099";
            };
          };
        };
      }
    ];

    # nixpkgs issue, open, no linked PRs (silent)
    "/repos/NixOS/nixpkgs/issues/900012" = {
      state = "open";
    };
    "/repos/NixOS/nixpkgs/issues/900012/timeline?per_page=100" = [ ];

    # External PR, merged
    "/repos/octocat/widget/pulls/900020" = {
      state = "closed";
      merged = true;
    };

    # External PR, open
    "/repos/octocat/widget/pulls/900021" = {
      state = "open";
      merged = false;
    };

    # External issue, closed
    "/repos/octocat/widget/issues/900022" = {
      state = "closed";
    };

    # External issue, open (silent)
    "/repos/octocat/widget/issues/900023" = {
      state = "open";
    };

    # External PR, open + a capitalized "Stale" label (case-insensitive match)
    "/repos/octocat/widget/pulls/900024" = {
      state = "open";
      merged = false;
      labels = [ { name = "Stale"; } ];
    };

    # External issue, open, with linked PR via timeline
    "/repos/octocat/widget/issues/900025" = {
      state = "open";
    };
    "/repos/octocat/widget/issues/900025/timeline?per_page=100" = [
      {
        event = "cross-referenced";
        source = {
          issue = {
            number = 900098;
            pull_request = {
              url = "https://api.github.com/repos/octocat/widget/pulls/900098";
            };
          };
        };
      }
    ];

    # External issue, open, no linked PRs (silent)
    "/repos/octocat/widget/issues/900026" = {
      state = "open";
    };
    "/repos/octocat/widget/issues/900026/timeline?per_page=100" = [ ];
  };

  # The fake curl looks up fixtures by a path-encoded basename.
  encodePath = path: builtins.replaceStrings [ "/" "?" "=" ] [ "_" "_q_" "_eq_" ] path;

  fixtureDir = pkgs.runCommand "nixpkgs-tracker-fixtures" { } ''
    mkdir -p $out
    ${pkgs.lib.concatStringsSep "\n" (
      pkgs.lib.mapAttrsToList (path: body: ''
        cat > "$out/${encodePath path}" <<'JSON'
        ${builtins.toJSON body}
        JSON
      '') fixtures
    )}
  '';

  # Fake curl: parses the URL out of argv, derives the fixture filename, and
  # writes <body>\n<status> per the real curl `-w '\n%{http_code}'` contract.
  fakeCurl = pkgs.writeShellApplication {
    name = "curl";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      url=""
      for arg in "$@"; do
        case $arg in
          https://*|http://*) url=$arg ;;
        esac
      done
      path=''${url#https://api.github.com}
      encoded=''${path//\//_}
      encoded=''${encoded//\?/_q_}
      encoded=''${encoded//=/_eq_}
      fixture="${fixtureDir}/$encoded"
      if [[ ! -f $fixture ]]; then
        printf 'FIXTURE MISS: %s\n' "$path" >&2
        printf '\n404'
        exit 22
      fi
      cat "$fixture"
      printf '\n200'
    '';
  };
in
{
  inherit fakeCurl;
}
