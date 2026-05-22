{
  pkgs,
  entries,
  timeoutSeconds,
  failOpen,
}:
let
  entriesJSON = builtins.toJSON (
    map (e: {
      inherit (e) url description;
      message = e.message or null;
      targetChannel = e.targetChannel;
    }) entries
  );
  template = builtins.readFile ./check.sh;
  body =
    builtins.replaceStrings
      [
        "@ENTRIES_JSON@"
        "@TIMEOUT_SECONDS@"
        "@FAIL_OPEN@"
      ]
      [
        entriesJSON
        (toString timeoutSeconds)
        (if failOpen then "1" else "0")
      ]
      template;
in
pkgs.writeShellApplication {
  name = "nixpkgs-tracker-check";
  runtimeInputs = with pkgs; [
    curl
    jq
    coreutils
  ];
  bashOptions = [
    "nounset"
    "pipefail"
  ];
  text = body;
}
