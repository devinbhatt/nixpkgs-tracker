# nixpkgs-tracker

A Nix extension that makes living on the bleeding edge less painful. Use overlays to fix an issue, get notified when they're no longer needed.

## Motivation

I run `nixos-unstable` on my personal systems. Most of the time, it's awesome: I can install almost anything I can possibly need from one repository, and I get the latest version of packages right as they come out.
But sometmes, you actually need to fix some instability: maybe there's [some package that won't build properly](https://github.com/NixOS/nixpkgs/issues/514113), blocking you from rebuilding your system
or you absolutely _need_ the a new patch from upstream that hasn't been pulled into nixpkgs yet. So you make some sort of "temporary fix" and go along with your day.

`nixpkgs-tracker` makes sure those fixes _stay temporary_ by allowing you to link a GitHub issue or PR, and prints a warning at rebuild time when they're closed, merged, or otherwise no longer needed.

## Usage

Add the flake to your inputs, pointing its `nixpkgs` at yours so the
tracker knows which channel you actually follow:

```nix
inputs.nixpkgs-tracker = {
  url = "github:devinbhatt/nixpkgs-tracker";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Import the module — `nixosModules.default` on NixOS, `darwinModules.default`
on nix-darwin:

```nix
imports = [ inputs.nixpkgs-tracker.nixosModules.default ];
```

Declare entries alongside the overlay they relate to. Entries aggregate
across every module:

```nix
{
  nixpkgs.overlays = [
    (final: prev: {
      firefox = prev.firefox.overrideAttrs (_: { /* ... temporary fix ... */ });
    })
  ];

  nixpkgs-tracker.entries = [
    {
      url = "github:NixOS/nixpkgs/pull/123456";
      description = "firefox crash-on-launch fix";
      # message = "Remove the firefox overlay.";  # optional
      # targetChannel = "staging-next";  # override per entry if cherry-picking
    }
    {
      url = "github:owner/project/issues/42";
      description = "upstream segfault on startup";
    }
  ];
}
```

URLs accept either `https://github.com/<owner>/<repo>/{issues,pull}/<n>`
or the flake-style shorthand `github:<owner>/<repo>/{issues,pull}/<n>`.

On every system rebuild, an activation script anonymously hits the GitHub
API for each entry and prints a `[nixpkgs-tracker] …` line when:

- **nixpkgs PR** — merged _and_ the merge commit has propagated to the
  entry's `targetChannel` (defaulting to your nixpkgs input's ref). Silent
  during staging → staging-next → master → nixpkgs-unstable. If the PR is
  still open but carries a _stale_ label, you get a heads-up that it may be
  abandoned.
- **nixpkgs issue** — closed (verify the fix and drop the overlay), or
  still open but now has a linked PR (consider tracking the PR instead).
- **Other repo** — issue closed, PR merged, or PR open-but-stale (bump the
  package / find another approach).

Network failures never fail the rebuild — and never block it either; the
check runs as a `system.activationScripts` hook, not at evaluation time
(pure Nix evaluation can't make HTTP calls).

### Options

| Option | Default | Description |
| --- | --- | --- |
| `nixpkgs-tracker.entries` | `[]` | List of entries (see below). |
| `nixpkgs-tracker.timeoutSeconds` | `5` | Per-request curl timeout. |
| `nixpkgs-tracker.failOpen` | `true` | Swallow network errors silently. |
| `nixpkgs-tracker.enable` | `true` | Master switch. |

#### Entry fields

| Field | Required | Description |
| --- | --- | --- |
| `url` | yes | GitHub issue/PR URL or `github:` shorthand. |
| `description` | yes | Short label shown in the warning banner. |
| `message` | no | Override for the action prompt. |
| `targetChannel` | no | nixpkgs branch this entry tracks. Defaults to your `inputs.nixpkgs` ref. |

### Testing

Two layers, both `nix flake check`-able except where noted:

- **Fixture tests** (`checks.fixture-test`) — run in the build sandbox with
  `curl` swapped for a fixture server; cover every branch of the check
  script (shipped / not-yet-propagated / open / closed-unmerged /
  cherry-picked / stale PRs, closed / linked-PR / silent issues, external
  issue/PR variants, unparseable URLs).
- **Live API test** — `nix run .#test-live` hits real GitHub against stable
  long-merged/long-closed targets to catch API drift. It can't be part of
  `nix flake check` because Nix builds have no network.

There's no line-coverage harness; the case matrix above is the coverage
story.

### CI

- `.github/workflows/check.yml` runs `nix flake check` (treefmt, eval-module,
  fixture-test) on every push and pull request.
- `.github/workflows/update-flake-lock.yml` runs weekly (Mondays) and on
  manual dispatch: `nix flake update` then opens a `flake.lock: weekly update`
  PR. That PR's `check` run only fires if a `FLAKE_LOCK_TOKEN` repo secret (a
  fine-grained PAT with contents + pull-requests + workflows write) is set —
  PRs opened with the built-in `GITHUB_TOKEN` don't trigger other workflows.
