#!/bin/bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
mud_directory="${MUD_SERVER_DIR:-$project_root/../mud}"
cd "$mud_directory"

if [[ ! -x fluffos/build/bin/driver ]]; then
    printf 'FluffOS is not built. Expected: %s/fluffos/build/bin/driver\n' "$mud_directory" >&2
    exit 1
fi

if [[ ! -f mudcore/include/mudcore.h ]]; then
    printf 'Initialize the game dependency first: git submodule update --init\n' >&2
    exit 1
fi

if [[ ! -f data/.env ]]; then
    cp data/.env.example data/.env
fi

# Keep the tracked server configuration intact. log/ ignores local runtime files.
sed 's/^# mud ip : 0.0.0.0$/mud ip : 127.0.0.1/' config.ini > log/new-zmud.local.ini
printf 'Starting local MUD. Connect to 127.0.0.1:6666 (UTF-8).\n'
exec fluffos/build/bin/driver log/new-zmud.local.ini
