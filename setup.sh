#!/usr/bin/env bash
set -euo pipefail
TMP=$(mktemp -d)
git clone --depth 1 https://github.com/2bbb/agmsg-hub.git "$TMP/agmsg-hub" 2>/dev/null
"$TMP/agmsg-hub/install.sh" "$@"
rm -rf "$TMP"
