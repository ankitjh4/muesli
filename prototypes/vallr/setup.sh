#!/bin/sh
set -eu

prototype_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_checkpoint=${1:-"$HOME/Downloads/VALLR.path"}
local_checkpoint="$prototype_dir/.models/VALLR.pth"
python_bin=${PYTHON_BIN:-/opt/homebrew/bin/python3.11}
expected_sha256=967667d61e705b0bc78d40a3ec80dd7ec449aa1d4d90a5e83c0d4289309ef374

if [ ! -x "$python_bin" ]; then
    echo "Python 3.11 was not found at $python_bin" >&2
    exit 1
fi
if [ ! -f "$source_checkpoint" ]; then
    echo "VALLR checkpoint was not found at $source_checkpoint" >&2
    exit 1
fi

actual_sha256=$(shasum -a 256 "$source_checkpoint" | awk '{print $1}')
if [ "$actual_sha256" != "$expected_sha256" ]; then
    echo "The source checkpoint checksum does not match the verified VALLR weights." >&2
    exit 1
fi

mkdir -p "$prototype_dir/.models"
if [ ! -f "$local_checkpoint" ]; then
    cp "$source_checkpoint" "$local_checkpoint"
fi

if [ ! -x "$prototype_dir/.venv/bin/python" ]; then
    "$python_bin" -m venv "$prototype_dir/.venv"
fi

"$prototype_dir/.venv/bin/python" -m pip install --upgrade pip
"$prototype_dir/.venv/bin/python" -m pip install -r "$prototype_dir/requirements.txt"

echo
echo "Setup complete. Validate the checkpoint with:"
echo "  $prototype_dir/.venv/bin/python $prototype_dir/vallr_prototype.py --check-only"
