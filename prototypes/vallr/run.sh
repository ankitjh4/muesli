#!/bin/sh
set -eu

prototype_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ ! -x "$prototype_dir/.venv/bin/python" ] || [ ! -f "$prototype_dir/.models/VALLR.pth" ]; then
    "$prototype_dir/setup.sh"
fi

exec "$prototype_dir/.venv/bin/python" "$prototype_dir/vallr_prototype.py" "$@"
