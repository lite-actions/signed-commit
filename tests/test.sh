#!/usr/bin/env bash
#
# Exercises commit.sh. The GraphQL call is stubbed with a fake `gh` on PATH, so
# the payload is asserted without touching the network. Run: bash tests/test.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/scripts/commit.sh"

pass=0
fail=0
check() {
  if [ "$2" -eq 0 ]; then echo "  ok   - $1"; pass=$((pass + 1))
  else echo "  FAIL - $1"; fail=$((fail + 1)); fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
cd "${tmp}" || exit 1

# A stub gh that records what it was asked to do and answers plausibly.
mkdir -p stub
cat > stub/gh <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  cat > "${GH_CAPTURE}"
  printf '{"data":{"createCommitOnBranch":{"commit":{"oid":"deadbeefcafe","url":"x"}}}}'
  exit 0
fi
# repos/<repo>/commits/<branch> - report a tip
case "$*" in
  *commits/*) printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; exit 0 ;;
  *git/refs*) printf '{}'; echo "REFS:$*" >> "${GH_CAPTURE}.refs"; exit 0 ;;
esac
printf '{}'
STUB
chmod +x stub/gh
export PATH="${tmp}/stub:${PATH}"
export GH_CAPTURE="${tmp}/payload.json"
export GITHUB_OUTPUT="${tmp}/out"

printf 'hello\n' > a.txt
printf 'world\n' > b.txt

run() { env INPUT_REPOSITORY="acme/widget" GH_TOKEN=x "$@" bash "${SCRIPT}"; }

# --- multi-file commit, headline only -------------------------------------
: > "${GITHUB_OUTPUT}"
run INPUT_BRANCH=topic INPUT_MESSAGE="docs: update" INPUT_FILES="$(printf 'a.txt\nb.txt')" >/dev/null 2>&1
check "multi-file commit succeeds" $?
jq -e '.variables.input.fileChanges.additions|length == 2' "${GH_CAPTURE}" >/dev/null
check "both files in one commit" $?
jq -e '.variables.input.message|has("body")|not' "${GH_CAPTURE}" >/dev/null
check "no empty body sent when message is one line" $?
jq -e '.variables.input.fileChanges.additions[0].contents == "aGVsbG8K"' "${GH_CAPTURE}" >/dev/null
check "file contents base64 encoded" $?
grep -q '^commit-sha=deadbeefcafe$' "${GITHUB_OUTPUT}"
check "emits commit-sha" $?

# --- headline and body ----------------------------------------------------
run INPUT_BRANCH=topic INPUT_MESSAGE="$(printf 'feat: thing\n\nwhy it matters')" INPUT_FILES=a.txt >/dev/null 2>&1
jq -e '.variables.input.message.headline == "feat: thing"' "${GH_CAPTURE}" >/dev/null
check "headline is the first line" $?
jq -e '.variables.input.message.body == "why it matters"' "${GH_CAPTURE}" >/dev/null
check "body is what follows the blank line" $?

# --- deletions ------------------------------------------------------------
run INPUT_BRANCH=topic INPUT_MESSAGE="chore: drop" INPUT_DELETED_FILES=gone.txt >/dev/null 2>&1
jq -e '.variables.input.fileChanges.deletions[0].path == "gone.txt"' "${GH_CAPTURE}" >/dev/null
check "deletions supported without additions" $?

# --- concurrency ----------------------------------------------------------
run INPUT_BRANCH=topic INPUT_MESSAGE="chore: x" INPUT_FILES=a.txt >/dev/null 2>&1
jq -e '.variables.input.expectedHeadOid == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' "${GH_CAPTURE}" >/dev/null
check "expectedHeadOid defaults to the branch tip" $?
run INPUT_BRANCH=topic INPUT_MESSAGE="chore: x" INPUT_FILES=a.txt INPUT_EXPECTED_HEAD_OID=beefbeef >/dev/null 2>&1
jq -e '.variables.input.expectedHeadOid == "beefbeef"' "${GH_CAPTURE}" >/dev/null
check "expected-head-oid overrides it" $?

# --- validation -----------------------------------------------------------
if run INPUT_BRANCH=topic INPUT_MESSAGE="chore: x" >/dev/null 2>&1; then
  check "refuses a commit with no changes" 1
else
  check "refuses a commit with no changes" 0
fi

if run INPUT_BRANCH=topic INPUT_MESSAGE="chore: x" INPUT_FILES=missing.txt >/dev/null 2>&1; then
  check "refuses a file that does not exist" 1
else
  check "refuses a file that does not exist" 0
fi

echo
echo "passed: ${pass}, failed: ${fail}"
[ "${fail}" -eq 0 ]
