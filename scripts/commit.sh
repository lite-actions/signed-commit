#!/usr/bin/env bash
#
# Create a commit through GitHub's GraphQL API, so GitHub signs it.
#
# A runner has no signing key, so `git commit` there produces an unsigned
# commit. On a branch with "require signed commits", a pull request containing
# one is blocked outright - GitHub evaluates the PR's commits before a merge
# strategy is chosen, so squashing does not rescue it. Commits created through
# the API are signed with GitHub's web-flow key, which sidesteps key custody.
#
# createCommitOnBranch rather than the REST contents endpoint: that one commits
# a single file per call, which would split a multi-file change across commits.
#
# Inputs (env):
#   INPUT_BRANCH             Branch to commit to.
#   INPUT_MESSAGE            Headline, then body after the first blank line.
#   INPUT_FILES              Newline-separated paths to add or update.
#   INPUT_DELETED_FILES      Newline-separated paths to delete.
#   INPUT_CREATE_BRANCH      Create the branch from INPUT_BASE_SHA first.
#   INPUT_BASE_SHA           Where to branch from.
#   INPUT_EXPECTED_HEAD_OID  Refuse unless the tip matches; default: read it.
#   INPUT_REPOSITORY         owner/repo.
#   GH_TOKEN                 Token with contents write.
#
# Output (to $GITHUB_OUTPUT): commit-sha
#
set -euo pipefail

: "${GITHUB_OUTPUT:=/dev/stdout}"

die() { echo "error: $*" >&2; exit 1; }

BRANCH="${INPUT_BRANCH:-}"
MESSAGE="${INPUT_MESSAGE:-}"
FILES="${INPUT_FILES:-}"
DELETED="${INPUT_DELETED_FILES:-}"
CREATE_BRANCH="${INPUT_CREATE_BRANCH:-false}"
BASE_SHA="${INPUT_BASE_SHA:-}"
EXPECTED="${INPUT_EXPECTED_HEAD_OID:-}"
REPO="${INPUT_REPOSITORY:-}"

[ -n "${BRANCH}" ]  || die "branch is required"
[ -n "${MESSAGE}" ] || die "message is required"
[ -n "${REPO}" ]    || die "repository is required"
[ -n "${FILES}" ] || [ -n "${DELETED}" ] || die "nothing to commit: set files, deleted-files, or both"

# Headline is the first line; body is whatever follows the first blank line.
# Parameter expansion rather than `head`, which trips SIGPIPE under pipefail.
headline="${MESSAGE%%$'\n'*}"
body=""
if [ "${MESSAGE}" != "${headline}" ]; then
  body="${MESSAGE#*$'\n'}"
  body="${body#$'\n'}"   # drop the blank separator line
fi

# --------------------------------------------------------------------------
# Branch: create it, or find out where its tip is.
# --------------------------------------------------------------------------
if [ "${CREATE_BRANCH}" = "true" ]; then
  [ -n "${BASE_SHA}" ] || die "base-sha is required when create-branch is true"
  gh api "repos/${REPO}/git/refs" \
    -f ref="refs/heads/${BRANCH}" -f sha="${BASE_SHA}" >/dev/null \
    || die "could not create branch ${BRANCH} at ${BASE_SHA}"
  : "${EXPECTED:=${BASE_SHA}}"
fi

if [ -z "${EXPECTED}" ]; then
  EXPECTED="$(gh api "repos/${REPO}/commits/${BRANCH}" --jq '.sha' 2>/dev/null)" \
    || die "branch ${BRANCH} does not exist - set create-branch: true to make it"
fi

# --------------------------------------------------------------------------
# File changes. base64 -w0 is GNU-only; this form also works on macOS.
# --------------------------------------------------------------------------
encode() { base64 < "$1" | tr -d '\n'; }

additions="[]"
if [ -n "${FILES}" ]; then
  additions="$(
    while IFS= read -r path; do
      [ -n "${path}" ] || continue
      [ -f "${path}" ] || die "file not found: ${path}"
      jq -n --arg path "${path}" --arg contents "$(encode "${path}")" \
        '{path: $path, contents: $contents}'
    done <<< "${FILES}" | jq -s '.'
  )"
fi

deletions="[]"
if [ -n "${DELETED}" ]; then
  deletions="$(
    while IFS= read -r path; do
      [ -n "${path}" ] || continue
      jq -n --arg path "${path}" '{path: $path}'
    done <<< "${DELETED}" | jq -s '.'
  )"
fi

# --------------------------------------------------------------------------
# Commit.
# --------------------------------------------------------------------------
payload="$(jq -n \
  --arg repo "${REPO}" \
  --arg branch "${BRANCH}" \
  --arg oid "${EXPECTED}" \
  --arg headline "${headline}" \
  --arg body "${body}" \
  --argjson additions "${additions}" \
  --argjson deletions "${deletions}" \
  '{
     query: "mutation($input:CreateCommitOnBranchInput!){createCommitOnBranch(input:$input){commit{oid url}}}",
     variables: {
       input: {
         branch: {repositoryNameWithOwner: $repo, branchName: $branch},
         expectedHeadOid: $oid,
         message: (if $body == "" then {headline: $headline}
                   else {headline: $headline, body: $body} end),
         fileChanges: {additions: $additions, deletions: $deletions}
       }
     }
   }')"

response="$(printf '%s' "${payload}" | gh api graphql --input -)"
sha="$(printf '%s' "${response}" | jq -r '.data.createCommitOnBranch.commit.oid // empty')"
[ -n "${sha}" ] || die "no commit returned: ${response}"

echo "Created signed commit ${sha} on ${BRANCH}."
printf 'commit-sha=%s\n' "${sha}" >> "${GITHUB_OUTPUT}"
