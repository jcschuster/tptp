#!/usr/bin/env bash
# Vendors the newest TPTP syntax BNF, if the published page announces a version newer
# than the one under priv/bnf, regenerates from it, and prepares the release that
# ships it: a minor version when the new BNF takes anything away (see bnf-breaks.exs),
# a patch version when it only adds. Run from the repository root:
#
#     .github/scripts/bnf-bump.sh REVIEW_FILE
#
# Writes `bnf`, `old`, `version` and `bump` (`minor` or `patch`) to $GITHUB_OUTPUT
# (stdout outside Actions); `bnf` is empty when the vendored BNF is current.
# REVIEW_FILE receives what a maintainer has to look at before merging: what the new
# BNF takes away, hand-written code that still names a rule or a $-word it dropped,
# and prose that still names the old version.
set -euo pipefail

review=${1:?usage: bnf-bump.sh REVIEW_FILE}
page=https://tptp.org/UserDocs/TPTPLanguage/SyntaxBNF.html
repo=TPTPWorld/SyntaxBNF
project=${GITHUB_REPOSITORY:-jcschuster/tptp}
out=${GITHUB_OUTPUT:-/dev/stdout}
today=$(date -u +%F)

# Exactly one, as Tptp.Bnf.vendored_path!/0 requires.
old_path=$(ls priv/bnf/SyntaxBNF-v*)
old=${old_path##*SyntaxBNF-v}
old_re=${old//./\\.}

# The page renders the BNF's own history comments, `% v9.3.1.6 - ...`, with &nbsp;.
new=$(curl -sSfL "$page" |
  grep -oE '%(&nbsp;)+v[0-9]+(\.[0-9]+)+&nbsp;-' |
  grep -oE '[0-9]+(\.[0-9]+)+' | sort -V | tail -n 1)

if [ -z "$new" ]; then
  echo "::error::no version found on $page; has the page's layout changed?"
  exit 1
fi

if [ "$(printf '%s\n' "$old" "$new" | sort -V | tail -n 1)" = "$old" ]; then
  echo "vendored BNF v$old is current (the page announces v$new)" >&2
  echo "bnf=" >>"$out"
  exit 0
fi

# NOTICE vendors the repository's file, not the page: the two have differed under
# one version number before. The page only says that a release exists.
sha=$(git ls-remote "https://github.com/$repo" HEAD | cut -f1)
date=$(curl -sSf "https://api.github.com/repos/$repo/commits/$sha" |
  jq -r .commit.committer.date | cut -c1-10)
url=https://raw.githubusercontent.com/$repo/$sha/SyntaxBNF-v$new
new_path=priv/bnf/SyntaxBNF-v$new

if ! curl -sSfL "$url" -o "$new_path"; then
  echo "::error::the page announces v$new, but $repo has no SyntaxBNF-v$new at ${sha:0:8}"
  rm -f "$new_path"
  exit 1
fi

digest=$(sha256sum "$new_path" | cut -d' ' -f1)

# The tests cannot say whether a release breaks callers: they pin the old file's rule
# counts and line numbers, which any release moves, and nothing fails when
# hand-written code names a node kind that no longer exists. The two BNFs can.
mix compile >&2
breaks=$(mix run --no-start --no-compile .github/scripts/bnf-breaks.exs "$old_path" "$new_path")

rules() { grep -oE '^<[A-Za-z0-9_]+>' "$1" | tr -d '<>' | sort -u; }
words() { grep -v '^%' "$1" | grep -oE '\$[a-z_]+' | sort -u; }

generated=(':!src/tptp_parser.yrl' ':!lib/tptp/bnf/vocabulary.ex'
  ':!lib/tptp/printer/shapes.ex' ':!test/support/bnf_oracle.ex'
  ':!lib/tptp/szs/ontology.ex')

{
  echo "### What v$new takes away"
  echo
  if [ -n "$breaks" ]; then
    sed 's/^/- /' <<<"$breaks"
  else
    echo "Nothing: every rule and alternative of v$old is still there, so this is a patch release."
  fi
  echo
  echo "### Removed rules still named by hand-written code"
  echo
  echo '```text'
  comm -23 <(rules "$old_path") <(rules "$new_path") | while read -r name; do
    git grep -nw "$name" -- lib checks test "${generated[@]}" || true
  done
  comm -23 <(words "$old_path") <(words "$new_path") | while read -r word; do
    git grep -nwF "$word" -- lib checks test "${generated[@]}" || true
  done
  echo '```'
} >"$review"

git rm -q "$old_path"

sed -i -E \
  -e "s#priv/bnf/SyntaxBNF-v$old_re#priv/bnf/SyntaxBNF-v$new#" \
  -e "s#syntax BNF, version $old_re,#syntax BNF, version $new,#" \
  -e "s#($repo at commit )[0-9a-f]+ of [0-9-]+:#\1${sha:0:8} of $date:#" \
  -e "s#$repo/[0-9a-f]{40}/SyntaxBNF-v$old_re#$repo/$sha/SyntaxBNF-v$new#" \
  -e "\#$repo/$sha/#{n;s#sha256 [0-9a-f]{64}#sha256 $digest#}" \
  NOTICE

sed -i "s#SyntaxBNF-v$old_re#SyntaxBNF-v$new#g" README.md test/tptp/vendored_test.exs
sed -i "s/syntax BNF (v$old_re)/syntax BNF (v$new)/" CITATION.cff .zenodo.json
sed -i "/iex> Tptp.bnf_version()/{n;s/\"$old_re\"/\"$new\"/}" lib/tptp.ex

{
  echo
  echo "### Hand-written prose still naming v$old"
  echo
  echo '```text'
  git grep -n "v$old_re" -- . ':!CHANGELOG.md' ':!reports' ':!priv' "${generated[@]}" || true
  echo '```'
} >>"$review"

version=$(grep -oE '@version "[^"]+"' mix.exs | cut -d'"' -f2)
IFS=. read -r major minor patch <<<"$version"
if [ -n "$breaks" ]; then
  bump=minor
  next=$major.$((minor + 1)).0
else
  bump=patch
  next=$major.$minor.$((patch + 1))
fi

sed -i "s/@version \"$version\"/@version \"$next\"/" mix.exs
sed -i -E "s/^version: \".*\"/version: \"$next\"/; s/^date-released: \".*\"/date-released: \"$today\"/" \
  CITATION.cff
sed -i -E "s/\"version\": \"[^\"]+\"/\"version\": \"$next\"/" .zenodo.json

# The BNF's history entries after the old version, up to the banner closing them.
history=$(awk -v old="% v$old " '
  /^% v/ { on = seen; if (index($0, old) == 1) seen = 1 }
  NR > 1 && /^%-/ { on = 0; seen = 0 }
  on' "$new_path")

section=$(mktemp)
cat >"$section" <<EOF
## [$next] - $today

### Changed

- The parser is regenerated from TPTP BNF v$new, which \`Tptp.bnf_version/0\` now
  reports; it was v$old. $([ -n "$breaks" ] && echo "This breaks callers that name what it removed:
$(sed 's/^/  - /' <<<"$breaks")

  ")The BNF records what changed:

  \`\`\`text
$(sed 's/^/  /' <<<"$history")
  \`\`\`

EOF

awk -v section="$section" \
  -v link="[$next]: https://github.com/$project/compare/v$version...v$next" '
  !s && /^## \[/ { while ((getline line < section) > 0) print line; s = 1 }
  !k && /^\[[0-9]/ { print link; k = 1 }
  { print }' CHANGELOG.md >CHANGELOG.md.new
mv CHANGELOG.md.new CHANGELOG.md
rm "$section"

mix tptp.gen

{
  echo "bnf=$new"
  echo "old=$old"
  echo "version=$next"
  echo "bump=$bump"
} >>"$out"
