#!/usr/bin/env bash
# Print the search index format and schema that the otzaria_search_engine
# pinned by a pubspec.lock writes, as "<INDEX_FORMAT> <INDEX_SCHEMA_VERSION>".
#
#   engine_index_schema.sh <pubspec.lock>
#
# Reads the engine's own source for the pinned revision (hosted, git or path),
# so neither Flutter nor a `pub get` is needed.
set -euo pipefail

pubspec_lock=${1:?usage: engine_index_schema.sh <pubspec.lock>}
[ -f "$pubspec_lock" ] || { echo "::error::pubspec.lock not found: $pubspec_lock" >&2; exit 1; }

fail() { echo "::error::$*" >&2; exit 1; }

# key=value for the package entry; description fields are prefixed "description.".
entry=$(awk '
  /^  otzaria_search_engine:$/ { inside = 1; next }
  inside && /^  [^ ]/ { exit }
  inside && /^    description:/ { section = "description."; next }
  inside && /^    [^ ]/ { section = "" }
  inside && /^ +[A-Za-z_-]+: / {
    line = $0; sub(/^ +/, "", line)
    key = line; sub(/:.*/, "", key)
    value = line; sub(/^[^:]+: /, "", value); gsub(/"/, "", value)
    print section key "=" value
  }
' "$pubspec_lock")
[ -n "$entry" ] || fail "$pubspec_lock pins no otzaria_search_engine"
field() { printf '%s\n' "$entry" | sed -n "s/^$1=//p" | head -n1; }

source_kind=$(field source)
version=$(field version)
engine_file=rust/src/api/search_engine.rs
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
source_path="$work/search_engine.rs"

case "$source_kind" in
  hosted)
    host=$(field description.url)
    curl -fsSL --retry 3 --retry-delay 5 "${host%/}/api/archives/otzaria_search_engine-$version.tar.gz" \
      | tar -xzf - -C "$work" "$engine_file" \
      || fail "cannot read $engine_file of otzaria_search_engine $version from $host"
    source_path="$work/$engine_file"
    ;;
  git)
    url=$(field description.url)
    ref=$(field description.resolved-ref)
    sub_path=$(field description.path)
    repo=${url#https://github.com/}; repo=${repo%/}; repo=${repo%.git}
    [ "$repo" != "$url" ] && printf '%s' "$repo" | grep -Eq '^[^/]+/[^/]+$' || fail "otzaria_search_engine comes from $url; only github.com git sources are supported"
    sub_path=${sub_path#.}; sub_path=${sub_path#/}
    curl -fsSL --retry 3 --retry-delay 5 -o "$source_path" \
      "https://raw.githubusercontent.com/$repo/$ref/${sub_path:+$sub_path/}$engine_file" \
      || fail "cannot read $engine_file of $repo at $ref"
    ;;
  path)
    package_path=$(field description.path)
    [ "$(field description.relative)" != true ] || package_path="$(dirname "$pubspec_lock")/$package_path"
    source_path="$package_path/$engine_file"
    [ -f "$source_path" ] || fail "search engine source not found: $source_path"
    ;;
  *) fail "unsupported otzaria_search_engine source '$source_kind' in $pubspec_lock" ;;
esac

# Same parsing as fetch_prebuilt_library_index.sh, which checks the stored index against these.
engine_const() { # engine_const <NAME>
  sed -nE "s/^(pub(\([a-z]+\))? )?const $1: [^=]+= \"?([^\";]+)\"?;.*/\3/p" "$source_path" | head -n1
}
format=$(engine_const INDEX_FORMAT)
schema=$(engine_const INDEX_SCHEMA_VERSION)
[ -n "$format" ] && [ -n "$schema" ] || fail "cannot read INDEX_FORMAT / INDEX_SCHEMA_VERSION from $source_path"
echo "$format $schema"
