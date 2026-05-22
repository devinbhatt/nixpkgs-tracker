# nixpkgs-tracker

A Nix extension that makes living on the bleeding edge less painful. Use overlays to fix an issue, get notified when they're no longer needed.

## Motivation

I run `nixos-unstable` on my personal systems. Most of the time, it's awesome: I can install almost anything I can possibly need from one repository, and I get the latest version of packages right as they come out.
But sometimes, you actually need to fix some instability: maybe there's a broken package blocking your, or you absolutely _need_ a new patch from upstream that hasn't been pulled in yet. So you make some "temporary" patch and go along with your day.

`nixpkgs-tracker` makes sure those patch _stay temporary_ by allowing you to link a GitHub issue or PR, and prints a warning at rebuild time when they're closed, merged, or otherwise no longer needed.

## Usage

Add the flake to your inputs:

```nix
# flake.nix
inputs.nixpkgs-tracker = {
  url = "github:devinbhatt/nixpkgs-tracker";
  inputs.nixpkgs.follows = "nixpkgs"; # nixpkgs-tracker uses your nixpkgs input to know what channel you're on
};
```

Import the module in your top-level system module list:

```nix
# NixOS
imports = [ inputs.nixpkgs-tracker.nixosModules.default ];

# nix-darwin
imports = [ inputs.nixpkgs-tracker.darwinModules.default ];
```

This exposes the `nixpkgs-tracker.*` options below and registers a `system.activationScripts.nixpkgs-tracker` entry that runs on every rebuild.

Declare entries alongside the overlay they relate to:

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
      # message = "Remove the firefox overlay.";  (optional)
      # targetChannel = "staging-next";  (optional override in case you're cherry-picking from a different nixpkgs release)
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

### Output

On every system rebuild, an activation script anonymously hits the GitHub API for each entry and prints to stderr in the form `[nixpkgs-tracker] <description>: {status}. <action>`.

| Scenario | Output | `message` overrides action? |
| --- | --- | --- |
| `nixpkgs` PR landed in `targetChannel` | `<desc>: PR #<n> has reached <channel>. Run 'nix flake update' and remove the overlay.` | yes |
| `nixpkgs` PR marked stale | `<desc>: PR #<n> is marked stale — it may be abandoned; consider an alternative.` | no |
| `nixpkgs` issue closed | `<desc>: issue #<n> is closed. Verify the fix and remove the overlay.` | yes |
| `nixpkgs` issue has linked PR | `<desc>: issue #<n> now has linked PR #<m> — consider tracking that instead.` | no |
| External PR merged | `<desc>: upstream <owner>/<repo> PR #<n> is merged. Bump the package and remove the overlay.` | yes |
| External issue closed | `<desc>: upstream <owner>/<repo> issue #<n> is closed. Bump the package and remove the overlay.` | yes |
| External issue has linked PR | `<desc>: upstream <owner>/<repo> issue #<n> now has linked PR #<m> — consider tracking that instead.` | no |
| External PR marked stale | `<desc>: upstream <owner>/<repo> PR #<n> is marked stale — it may be abandoned; consider an alternative.` | no |

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

Two layers:

- **Fixture tests** (`checks.fixture-test`, run by `nix flake check`): run in
  the build sandbox with `curl` swapped for a fixture server; cover every
  branch of the check script.
- **Live API test** (`nix run .#test-live`): hits real GitHub against stable
  long-merged/long-closed targets to catch API drift.
