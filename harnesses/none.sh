#!/bin/sh
# devbox harness — none. Selected with ARG HARNESS when a project wants the
# toolchain layer only: no agent, no runtime, no settings written (D2).
#
# It exists so the harness slot is always filled by exactly one script — the
# build never guesses, and adding a harness stays one new file.
set -eu
echo "devbox harness: none"
