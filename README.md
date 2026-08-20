# Signed Commit Lite

Create a commit that **GitHub signs**, without a signing key on the runner.
Pure shell — no Node, no Docker, just `bash`, `gh` and `jq`.

## The problem

A runner has no signing key, so `git commit` there produces an **unsigned**
commit. On a branch with *Require signed commits*, a pull request containing one
is blocked outright — and no merge strategy rescues it, because GitHub evaluates
the PR's commits before you get to choose one:

```
mergeable: MERGEABLE      unresolved: 0
reviewDecision: APPROVED  signature: null
mergeStateStatus: BLOCKED
```

Everything passes; the branch still cannot merge. The usual advice — squash it —
does not work.

Commits created through GitHub's API are signed with its web-flow key. This
action makes that commit for you, so no key ever has to live in a secret.

## Usage

```yaml
- uses: lite-actions/git-checkout@v1

- run: ./generate-some-files.sh

- uses: lite-actions/signed-commit@v1
  id: commit
  with:
    branch: chore/update-${{ github.run_id }}
    create-branch: true
    message: "docs: update generated files"
    files: |
      CHANGELOG.md
      RELEASE_NOTES.md
    token: ${{ secrets.BOT_TOKEN }}

- run: echo "committed ${{ steps.commit.outputs.commit-sha }}"
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `branch` | — | Branch to commit to. Required. |
| `message` | — | First line is the headline; anything after the first blank line becomes the body. Required. |
| `files` | `""` | Newline-separated paths to add or update. Binary files are fine. |
| `deleted-files` | `""` | Newline-separated paths to delete. |
| `create-branch` | `false` | Create the branch from `base-sha` first. |
| `base-sha` | `github.sha` | Commit to branch from when creating. |
| `expected-head-oid` | branch tip | Refuse unless the tip matches — optimistic concurrency. |
| `repository` | `github.repository` | Repository to commit to. |
| `token` | `github.token` | Needs **contents: write**. |

At least one of `files` or `deleted-files` must be set.

## Outputs

| Output | Description |
| --- | --- |
| `commit-sha` | SHA of the commit that was created. |

## Notes

**The token matters more than it looks.** `GITHUB_TOKEN` works for committing,
but a branch pushed with it does **not** trigger workflows — so if the commit
opens a pull request that needs required checks, use a user PAT instead.

**Multiple files land in one commit.** The REST contents endpoint commits one
file per call; this uses the GraphQL `createCommitOnBranch` mutation, which
takes them together.

**Concurrency is checked by default.** `expected-head-oid` defaults to the
branch's current tip, so a commit racing another one fails rather than
clobbering it. Pass it explicitly to pin to a known SHA.

## Licence

MIT.
