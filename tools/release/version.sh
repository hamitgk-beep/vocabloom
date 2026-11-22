#!/usr/bin/env bash
# User-facing version of a commit: every first-parent commit on main after
# the base commit adds 0.1 (1.1, 1.2 ... 1.9, 2.0 ...). The same formula was
# inlined in build.yml before the release was split off into release.yml;
# both now call this script so a build and its release always agree.
#
#   tools/release/version.sh [commit]   (default HEAD; needs full history)
set -euo pipefail
sha=${1:-HEAD}
base=9cedfea
k=$(git rev-list --count --first-parent "$base..$sha")
echo "$(( 1 + k / 10 )).$(( k % 10 ))"
