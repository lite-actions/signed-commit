# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## Scope

A composite **GitHub Action** (pure shell) that creates a commit **GitHub
signs**, without a signing key on the runner. Published to the Marketplace as
**Signed Commit Lite**.

A runner has no signing key, so `git commit` there is unsigned — and a pull
request containing an unsigned commit is blocked outright where signatures are
required. Squashing does not rescue it: GitHub evaluates the PR's commits before
the merge strategy applies. This action commits through GitHub's GraphQL
`createCommitOnBranch`, which signs server-side.

## Layout

- `action.yml` — composite action; inputs for branch, message, files,
  deleted-files, create-branch, base-sha, expected-head-oid, repository, token.
  Output: `commit-sha`.
- `scripts/commit.sh` — all the logic.
- `tests/test.sh` — stubs `gh` on `PATH` to assert the GraphQL payload without
  touching the network.

## Coding style

- Pure `bash` with `set -euo pipefail`; must pass
  `shellcheck -x --severity=warning` (CI enforces).
- Base64 encoding must stay portable: `base64 < "$f" | tr -d '\n'` works on both
  macOS and Linux; `base64 -w0` does not exist on macOS.
- Prefer parameter expansion over `sed | head` — SIGPIPE under `pipefail`.

## Conventions

- Public repo with a **protected `main`** — all changes go via PR.
- Conventional Commits for messages. **Branch types are a different list from
  commit types**: branches allow only `feature bugfix hotfix release chore`, so
  `fix/…` and `docs/…` are invalid branch names and a PR's head branch cannot be
  renamed. Use `chore/…` when unsure.
- Co-authored commits use the bot identity:
  `Co-Authored-By: Claude <309050497+MrDClaudeBot@users.noreply.github.com>`
- **Never use `git worktree`.** Push from the current branch with
  `git push origin HEAD:<branch>`, or use a fresh clone.
- **Never use `pull_request_target`.** It runs the *base* repository's workflow
  with secrets and a write token against fork-controlled code — the classic way
  an action repository is compromised. `pull_request` is correct: a fork PR runs
  in the fork's context with a read-only token and no access to secrets, so
  untrusted code still runs but can neither exfiltrate nor write. This is the
  single most important control here and the cheapest to lose by accident,
  because `pull_request_target` looks like a convenient way to get a token.

## Versioning & publishing

Releases are cut by `publish.yml` (`workflow_dispatch`) — never by hand, and
never through the GitHub web UI:

```bash
gh workflow run publish.yml --repo lite-actions/signed-commit
```

It is `publish.yml`, not `release.yml`, because this action **is** listed: the
Marketplace listing tracks the GitHub Release, so releasing is how it publishes.
Something published nowhere would use `release.yml` instead.

The workflow computes the version from commits since the last `vX.Y.Z` tag, tags
the release, force-moves `@vN`, and publishes the Release with the generated
notes as its body. It releases nothing when there are no BREAKING/feat/fix
commits, and says `NO RELEASE CHANGES`.

**Never create a release through the web UI.** The Marketplace checkbox is
required only for an action's *first* publish; afterwards the listing tracks
releases automatically. Using the UI is what produced malformed tags and left
moving major tags stale elsewhere in this org.
