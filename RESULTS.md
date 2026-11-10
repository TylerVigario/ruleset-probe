# Results

Measured 2026-11-10 (UTC) on this repository, by attempt. The admin account is the
actor throughout; whether it may pass `version-tag-protection` was set by that
ruleset's bypass list, which is the only thing that changed between runs. Each
row is a refusal or an admission GitHub returned, not a reading of configuration.

## A bypass actor must be installed

The GitHub Actions app (integration 15368) cannot be a bypass actor here:

```text
422 Actor GitHub Actions integration must be part of the ruleset source or owner organization
```

So the bypass side was measured with the admin role (`RepositoryRole` 5) as the
bypass actor, and the refused side with no bypass actor at all.

## Creation, restricted (`creation` on `refs/tags/v*` and `refs/tags/v*/**/*`)

| Attempt on a new `v` tag | No bypass | Bypass actor |
| --- | --- | --- |
| `git push` | refused: `GH013 … Cannot create ref due to creations being restricted` | allowed |
| refs API `POST git/refs` | refused: `422 Reference update failed` | allowed |
| publishing a release (`gh release create`) | refused: `422 … Published releases must have a valid tag` | allowed |
| publishing a draft (`gh release edit --draft=false`) | refused, and the release stays a draft | allowed |
| `v6/nested`, `v6/a/b` | refused | allowed |

## Composition

The bypass actor of `version-tag-protection` is past `creation` and nothing in
`tag-protection`: every move and delete of a tag it created was refused —
`Cannot update this protected ref`, `Cannot delete this tag` — by `git push --force`,
by the refs API fast-forward and by delete, for `v7.0.x` and for `v7/nested`, `v7/a/b`.
A non-force `git push` of an existing tag is refused by git itself (`already exists`)
before GitHub sees it, so that row says nothing about the rule.

## Patterns (`File::FNM_PATHNAME`: `*` stops at `/`)

| `include` | `vN.0.0` | `vN/nested` |
| --- | --- | --- |
| `refs/tags/v*` | covered | **not covered**: created, moved, forced and deleted |
| `refs/tags/v**` | covered | **not covered** |
| `refs/tags/v**/**/*` | **not covered** | covered |
| `refs/tags/v*/**/*` | **not covered** | covered |
| `refs/tags/v*` + `refs/tags/v*/**/*` | covered | covered, and `vN/a/b` |

| `tag-protection` `include` | `qN` | `sN/nested`, `sN/a/b` |
| --- | --- | --- |
| `refs/tags/*` | protected | **unprotected**: moved, forced and deleted |
| `refs/tags/**` | protected | **unprotected** |
| `refs/tags/**/*` | protected | protected |

`git tag --list 'v*' --sort=-v:refname` matches across `/` and lists `v9/x` above
`v1.21.1`.

## Read-back and the log

A creation-only tag ruleset reads back exactly as sent, with no field added. The
rule-suites log (`GET rulesets/rule-suites`) records a bypass as `bypass`, with
the actor, and a refusal as `fail`, with the rule and ruleset that refused it.

## A release commit, checked (`decide`)

Synthetic release commits, constructed by GitHub through `createCommitOnBranch`
as a release's are, with the expected author set to the account that made them:

| Case | Result |
| --- | --- |
| only the version and changelog changed, published release | finishes |
| the same, expecting a different author | refused: the release's author |
| an extra file changed | refused: the files |
| `package.json` changed beyond its version | refused |
| `package-lock.json` changed beyond its version | refused |
| `package-lock.json`'s root package left at the old version | refused: the version |
| the release still a draft | refused: no published release (404) |
| an unsigned commit through the git data API | refused: `false unsigned` |

## A branch bypass reaches every rule in its ruleset

Measured 2026-11-10 (UTC) on `trunk-a`, `trunk-b` and `trunk-c`, each created at
`d23aaff` before any branch ruleset existed. The admin role stands in for the
release App, as above. The payloads in `rulesets/branch-*.json` are the website's
`main.json` with three things changed: `include` is `refs/heads/trunk-*` instead of
`~DEFAULT_BRANCH`, the bypass actor is the admin role, and the one required check is
`Never reports`, which nothing reports. Each attempt starts where the one before it
left the branch (`evidence/branch-probe.sh`).

| Attempt, as the bypass actor | One ruleset, bypass on it | Split: bypass on the merge rules only | Split, no bypass |
| --- | --- | --- | --- |
| refs API `force=false` fast-forward, the release's move | allowed | allowed | refused: pull request, required check, code scanning |
| `git push` fast-forward | allowed | allowed | refused: the same three |
| `git push` of a merge commit, as a fast-forward | allowed | refused: `This branch must not contain merge commits` | |
| `git push --force` backward | allowed | refused: `Cannot force-push to this branch` | |
| refs API `force=true` backward | allowed | refused: the same | |
| refs API delete | allowed | refused: `Cannot delete this branch` | |
| `git push` delete | void: already deleted | refused: the same | |

The split is `main-protection` holding `pull_request`, `required_status_checks` and
`code_scanning`, with the bypass, beside `main-history-protection` holding
`deletion`, `non_fast_forward` and `required_linear_history`, with none.

The rule log says it in its own terms (`evidence/23-rule-suites-branch.txt`). Under
one ruleset, the merge commit, both rewinds and the delete each record
`required_linear_history`, `non_fast_forward` or `deletion` as `fail`, and the push
as `bypass`. Under the split, the release's move records `main-protection`'s three
rules as `fail` and the push as `bypass`, with `main-history-protection`'s three as
`pass`: a linear fast-forward needs nothing from them.
