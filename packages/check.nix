{
  pkgs,
  entries ? [ ],
  timeoutSeconds ? 5,
  failOpen ? true,
}:
import ../lib/mk-check.nix {
  inherit
    pkgs
    entries
    timeoutSeconds
    failOpen
    ;
}
