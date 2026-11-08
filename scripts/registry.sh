#!/usr/bin/env bash
# Packs, checks and indexes every plugin under plugins/ into a registry
# format 1 index (the app repo's docs/plugins.md §8.1).
#
#   scripts/registry.sh check [--local]
#       Pack every plugin into out/packages/, check it, and write the next
#       index to out/site/index.json. Writes nothing remote. With --local, new
#       versions point at their file:// package, so the app can install from
#       out/site/index.json before anything is published.
#   scripts/registry.sh publish
#       `check`, then create one GitHub Release per new version, with its
#       package as the asset. CI only: needs GH_TOKEN. The workflow deploys
#       out/site/ to GitHub Pages afterwards.
#
# Published versions are immutable. Every run rebuilds each package and, for a
# version the live index already lists, requires the same sha256: changing a
# plugin means bumping `version` in its plugin.toml.
#
# Run inside `nix develop`: the package bytes depend on the tar and gzip
# builds, which flake.lock pins for local runs and CI alike.
#
# Environment:
#   REGISTRY_BASE  The index to compare against instead of registry.toml's
#                  `index_url`: a URL, a path, or `none` for an empty registry.
set -euo pipefail
cd "$(dirname "$0")/.."
shopt -s nullglob

# The app's install limits (crates/harness/src/plugins/install.rs).
readonly MIB=$((1024 * 1024))
readonly MAX_ARCHIVE=$((16 * MIB)) MAX_FILE=$((16 * MIB)) MAX_TOTAL=$((64 * MIB))

readonly SEMVER='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

# jq: a sort key giving SemVer 2.0 precedence (build metadata ignored; a
# release sorts above its pre-releases; numeric identifiers below text ones).
# shellcheck disable=SC2016 # a jq program: `$v` is jq's, not the shell's
readonly JQ_SEMVER='
def semkey:
  split("+")[0] as $v
  | ($v | index("-")) as $i
  | (if $i == null then $v else $v[:$i] end | split(".") | map(tonumber)) as $core
  | (if $i == null then null else $v[$i + 1:] end) as $pre
  | $core + (if $pre == null then [1]
             else [0] + ($pre | split(".") | map(if test("^[0-9]+$") then [0, tonumber] else [1, .] end))
             end);
'

problems=()
problem() { problems+=("$*"); }
note() { printf '%s\n' "$*" >&2; }
die() {
  note "error: $*"
  exit 1
}

usage() {
  sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0" >&2
  exit 2
}

# Fills $name, $repository, $index_url from registry.toml.
read_config() {
  local config
  config=$(yq -p toml -o json registry.toml) || die "registry.toml does not parse"
  name=$(jq -r '.name // empty' <<<"$config")
  repository=$(jq -r '.repository // empty' <<<"$config")
  index_url=$(jq -r '.index_url // empty' <<<"$config")
  [[ -n $name && -n $repository && -n $index_url ]] ||
    die "registry.toml needs name, repository and index_url"
  if [[ -n ${GITHUB_REPOSITORY:-} && ${GITHUB_REPOSITORY,,} != "${repository,,}" ]]; then
    die "registry.toml names $repository, but this runs in $GITHUB_REPOSITORY"
  fi
}

# Writes the index to compare against to out/base.json.
read_base() {
  local src=${REGISTRY_BASE:-$index_url}
  if [[ $src == none ]]; then
    echo '{"registry":1,"name":"","plugins":[]}' >out/base.json
  elif [[ $src == http://* || $src == https://* ]]; then
    # The query string skips the Pages CDN cache, so a publish right after
    # another one sees the index that one deployed.
    local code
    code=$(curl -sS -L -o out/base.json -w '%{http_code}' "$src?fresh=$(date +%s)") ||
      die "can't fetch the published index $src"
    case $code in
      200) ;;
      404)
        note "No index at $src yet: comparing against an empty registry."
        echo '{"registry":1,"name":"","plugins":[]}' >out/base.json
        ;;
      *) die "$src answered HTTP $code" ;;
    esac
  else
    cp -- "${src#file://}" out/base.json || die "can't read $src"
  fi
  jq -e '.registry == 1 and (.plugins | type) == "array"' out/base.json >/dev/null ||
    die "$src is not a registry format 1 index"
}

# The manifest problems the registry can see, one per line. The rest of the
# manifest (tools, schemas, views, the Luau source) is validated by the app
# when it installs the package.
# shellcheck disable=SC2016 # a jq program: `$k` is jq's, not the shell's
readonly JQ_MANIFEST='
def text($k):
  if (.[$k] | type) == "string" and (.[$k] | length) > 0 then empty
  else "`\($k)` must be a non-empty string" end;
[
  (if (.id | type) != "string" or (.id | test("^[a-z][a-z0-9-]*$") | not)
   then "`id` must be a lowercase letter followed by a-z, 0-9 or -"
   elif .id != $folder then "`id` is \(.id | tojson), but the folder is plugins/\($folder)"
   else empty end),
  (if (.version | type) == "string" then empty else "`version` must be a string" end),
  (if (.api | type) == "number" and .api >= 1 and (.api | floor) == .api then empty
   else "`api` must be a whole number, 1 or more" end),
  text("title"), text("description"), text("use_when"), text("avoid_when"),
  (if (.platforms | type) == "array" and (.platforms | length) > 0
      and all(.platforms[]; . == "desktop" or . == "mobile")
      and (.platforms | unique | length) == (.platforms | length)
   then empty else "`platforms` must be a non-empty subset of [desktop, mobile]" end),
  (if (.permissions // []) == [] then empty
   else "`permissions` must be empty: registry packages are Luau plugins, which the app runs with no access to files, network or programs" end)
] | .[]'

# Packs and checks plugins/$1; on success appends its index entry to
# out/entries.jsonl and, for a new version, a release record to out/new.jsonl.
plugin() {
  local id=$1
  local dir=plugins/$id
  if [[ ! -f $dir/plugin.toml ]]; then
    problem "$dir: no plugin.toml"
    return
  fi
  local manifest issues
  if ! manifest=$(yq -p toml -o json "$dir/plugin.toml" 2>&1); then
    problem "$dir/plugin.toml: $manifest"
    return
  fi
  issues=$(jq -r --arg folder "$id" "$JQ_MANIFEST" <<<"$manifest")
  if [[ -n $issues ]]; then
    while IFS= read -r line; do problem "$dir/plugin.toml: $line"; done <<<"$issues"
    return
  fi
  local version api title
  version=$(jq -r .version <<<"$manifest")
  api=$(jq -r .api <<<"$manifest")
  title=$(jq -r .title <<<"$manifest")
  if [[ ! $version =~ $SEMVER ]]; then
    problem "$dir/plugin.toml: \`version\` $version is not semver (e.g. 0.1.0)"
    return
  fi

  # Dotfiles are never packed; everything else must be a plain file or folder.
  local odd big total=0 size
  odd=$(find "$dir" -name '.*' -prune -o ! -type f ! -type d -print)
  if [[ -n $odd ]]; then
    problem "$dir: only plain files and folders can be packed, not: ${odd//$'\n'/, }"
    return
  fi
  big=$(find "$dir" -name '.*' -prune -o -type f -size +$((MAX_FILE / 1024))k -print)
  if [[ -n $big ]]; then
    problem "$dir: over $((MAX_FILE / MIB)) MiB, which the app refuses: ${big//$'\n'/, }"
    return
  fi
  while IFS= read -r size; do total=$((total + size)); done \
    < <(find "$dir" -name '.*' -prune -o -type f -printf '%s\n')
  if ((total > MAX_TOTAL)); then
    problem "$dir: $((total / MIB)) MiB of files; the app refuses packages over $((MAX_TOTAL / MIB)) MiB"
    return
  fi

  # Reproducible: sorted members, fixed owner, mode and time, no gzip header
  # name or time. One top-level folder, <id>-<version>/, as the app expects.
  local package=out/packages/$id-$version.tar.gz
  tar --create --format=gnu --sort=name --owner=0 --group=0 --numeric-owner \
    --mtime=@0 --mode='a=rX,u+w' --exclude='.*' \
    --directory=plugins --transform="s,^$id,$id-$version," "$id" |
    gzip -9 -n >"$package"
  if (($(stat -c %s "$package") > MAX_ARCHIVE)); then
    problem "$dir: the package is over $((MAX_ARCHIVE / MIB)) MiB, which the app refuses"
    return
  fi
  local sha
  sha=$(sha256sum "$package" | cut -d ' ' -f 1)

  local published listed release=null status
  published=$(jq -c --arg id "$id" '[.plugins[] | select(.id == $id) | .versions[]?]' out/base.json)
  listed=$(jq -r --arg v "$version" '.[] | select(.version == $v) | .sha256 | ascii_downcase' <<<"$published")
  if [[ -n $listed ]]; then
    if [[ $listed != "$sha" ]]; then
      problem "$dir: $version is already published, and the folder no longer packs to it (published sha256 $listed, now $sha). Bump \`version\` in plugin.toml."
      return
    fi
    status=published
  else
    local higher
    higher=$(jq -r --arg v "$version" "$JQ_SEMVER"'
      [.[].version | select(semkey >= ($v | semkey))] | sort_by(semkey) | last // empty' <<<"$published")
    if [[ -n $higher ]]; then
      problem "$dir: version $version is not above the published $higher; versions only go up"
      return
    fi
    local tag=$id-v$version url
    if ((local_urls)); then
      url="file://$PWD/$package"
    else
      url="https://github.com/$repository/releases/download/$tag/$id-$version.tar.gz"
    fi
    release=$(jq -cn --arg version "$version" --argjson api "$api" --arg url "$url" \
      --arg sha "$sha" --arg date "$(date -u +%F)" \
      '{version: $version, api: $api, url: $url, sha256: $sha, published: $date}')
    jq -cn --arg id "$id" --arg version "$version" --arg tag "$tag" --arg file "$package" \
      --arg sha "$sha" --arg title "$title" \
      '{id: $id, version: $version, tag: $tag, file: $file, sha256: $sha, title: $title}' >>out/new.jsonl
    status=new
  fi

  # Metadata comes from the folder (the newest version); every published
  # version stays listed.
  jq -cn --argjson m "$manifest" --argjson published "$published" --argjson release "$release" \
    "$JQ_SEMVER"'{
      id: $m.id, title: $m.title, description: $m.description,
      use_when: $m.use_when, avoid_when: $m.avoid_when,
      platforms: $m.platforms, permissions: ($m.permissions // []),
      versions: ($published + (if $release then [$release] else [] end) | sort_by(.version | semkey))
    }' >>out/entries.jsonl
  printf '  %-24s %-12s %-10s %s\n' "$id" "$version" "$status" "$sha" >&2
}

check() {
  read_config
  rm -rf out
  mkdir -p out/packages out/site
  : >out/entries.jsonl
  : >out/new.jsonl
  read_base

  local dirs=(plugins/*/)
  ((${#dirs[@]})) || note "No plugins yet: the index will list none."
  for dir in "${dirs[@]}"; do
    dir=${dir%/}
    plugin "${dir#plugins/}"
  done

  if ((${#problems[@]})); then
    note ""
    note "${#problems[@]} problem(s):"
    for p in "${problems[@]}"; do note "  - $p"; done
    exit 1
  fi

  # Published plugins whose folder is gone stay listed: learners may have
  # them installed, and a published version is never withdrawn.
  jq -r --slurpfile entries out/entries.jsonl \
    '.plugins[] | select(.id | IN($entries[].id) | not) | "  \(.id): no folder; kept as published"' \
    out/base.json >&2
  jq -n --arg name "$name" --slurpfile base out/base.json --slurpfile entries out/entries.jsonl '
    {
      registry: 1,
      name: $name,
      plugins: ($entries + [$base[0].plugins[] | select(.id | IN($entries[].id) | not)] | sort_by(.id))
    }' >out/site/index.json
  note ""
  note "Wrote out/site/index.json: $(jq '.plugins | length' out/site/index.json) plugin(s), $(wc -l <out/new.jsonl) new version(s)."
}

publish() {
  [[ -n ${GH_TOKEN:-} ]] || die "publish needs GH_TOKEN (the workflow passes github.token)"
  local_urls=0
  check

  # Every release must still be in the index; otherwise the index fetched as
  # the base was stale or lost, and deploying would drop published versions.
  local missing
  missing=$(comm -23 \
    <(gh release list --repo "$repository" --limit 10000 --json tagName --jq '.[].tagName' | sort) \
    <(jq -r '.plugins[] | .id as $id | .versions[] | "\($id)-v\(.version)"' out/site/index.json | sort))
  [[ -z $missing ]] ||
    die "these releases are missing from the next index; restore the published index before publishing: ${missing//$'\n'/, }"

  local record id version tag file sha title
  while IFS= read -r record; do
    id=$(jq -r .id <<<"$record")
    version=$(jq -r .version <<<"$record")
    tag=$(jq -r .tag <<<"$record")
    file=$(jq -r .file <<<"$record")
    sha=$(jq -r .sha256 <<<"$record")
    title=$(jq -r .title <<<"$record")
    if gh release view "$tag" --repo "$repository" >/dev/null 2>&1; then
      # A rerun after a failed deploy: the release must hold the same bytes.
      local tmp
      tmp=$(mktemp -d)
      gh release download "$tag" --repo "$repository" --pattern "$(basename "$file")" --dir "$tmp"
      [[ $(sha256sum "$tmp/$(basename "$file")" | cut -d ' ' -f 1) == "$sha" ]] ||
        die "release $tag already exists with other contents"
      rm -rf "$tmp"
      note "Release $tag already exists with these bytes."
    else
      gh release create "$tag" "$file" --repo "$repository" \
        --target "${GITHUB_SHA:-$(git rev-parse HEAD)}" \
        --title "$title $version" \
        --notes "Plugin \`$id\` $version. sha256: \`$sha\`"
      note "Released $tag."
    fi
  done <out/new.jsonl
}

local_urls=0
case ${1:-} in
  check)
    case ${2:-} in
      --local) local_urls=1 ;;
      "") ;;
      *) usage ;;
    esac
    check
    ;;
  publish) publish ;;
  *) usage ;;
esac
