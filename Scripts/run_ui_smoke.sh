#!/bin/zsh

set -euo pipefail

root_directory="$(cd "$(dirname "$0")/.." && pwd)"
bundle_identifier="com.temelgunaydin.finallyexplorer"

cd "$root_directory"

if flowdeck ui mac list apps --json | grep -q "\"bundle_id\" : \"$bundle_identifier\""; then
    print -u2 "Finally Explorer is already running. Quit it before running the UI smoke test."
    exit 2
fi

cleanup() {
    flowdeck ui mac quit --app "$bundle_identifier" --json >/dev/null 2>&1 || true
}
trap cleanup EXIT

flowdeck build --json
flowdeck ui mac check-permissions --json
flowdeck ui mac launch --bundle-id "$bundle_identifier" --background --json

flowdeck ui mac assert visible "Favorites" --app "$bundle_identifier" --json
flowdeck ui mac assert visible "Media" --app "$bundle_identifier" --json
flowdeck ui mac assert visible "Locations" --app "$bundle_identifier" --json
flowdeck ui mac assert visible "Add" --app "$bundle_identifier" --json
flowdeck ui mac assert visible "Search in Downloads" --app "$bundle_identifier" --json
flowdeck ui mac assert visible "Ask Explorer" --app "$bundle_identifier" --json

flowdeck ui mac click "Split Right" --app "$bundle_identifier" --background --json
flowdeck ui mac assert visible "Close Pane" --app "$bundle_identifier" --json
flowdeck ui mac click "Split Below" --app "$bundle_identifier" --background --json
flowdeck ui mac assert visible "Close Pane" --app "$bundle_identifier" --json
flowdeck ui mac click "Close Pane" --app "$bundle_identifier" --background --json
flowdeck ui mac click "Close Pane" --app "$bundle_identifier" --background --json
flowdeck ui mac assert hidden "Close Pane" --app "$bundle_identifier" --json

print "Finally Explorer UI smoke test passed."
