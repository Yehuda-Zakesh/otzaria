#!/usr/bin/env bash
set -euo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT

"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -Wpedantic \
  "$test_dir/splash_timeline_test.cpp" \
  -o "$fixture_dir/splash_timeline_test"
"$fixture_dir/splash_timeline_test"
