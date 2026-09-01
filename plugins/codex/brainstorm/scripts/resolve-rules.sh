#!/bin/bash
# resolve custom rules file through the two-layer override chain
# usage: resolve-rules.sh <filename>
#
# checks in order (first-found-wins, not merged):
#   1. .codex/<filename> (project override)
#   2. $CODEX_HOME/cc-thingz/brainstorm/<filename> (user override)
#
# outputs file content to stdout if found, empty output if not
# always exits 0

filename="$1"
if [ -z "$filename" ]; then
    exit 0
fi

codex_home="${CODEX_HOME:-$HOME/.codex}"
data_dir="$codex_home/cc-thingz/brainstorm"

if [ -f ".codex/$filename" ] && [ -s ".codex/$filename" ]; then
    cat ".codex/$filename"
elif [ -f "$data_dir/$filename" ] && [ -s "$data_dir/$filename" ]; then
    cat "$data_dir/$filename"
fi

exit 0
