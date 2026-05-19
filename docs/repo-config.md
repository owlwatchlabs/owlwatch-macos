# Repository configuration

Canonical specification of GitHub repository settings for `nightwatch`. The
GitHub UI is the source of truth for *applied* configuration; this document
is the source of truth for *intended* configuration. Any drift is a bug.

When a setting changes, update this document in the same PR that proposes
the change. When applying the change in the GitHub UI, reference this
document and the merged PR.

---

## Repository-level settings

**Settings → General → Pull Requests**

- [x] Allow squash merging — *default merge commit message:* "Pull request title and description"
- [x] Allow rebase merging
- [ ] Allow merge commits — **disabled**
- [x] Automatically delete head branches
- [ ] Allow auto-merge — disabled until CI maturity allows it
- [x] Always suggest updating pull request branches

**Settings → General → Features**

- [x] Issues
- [x] Projects (used for the Roadmap board, see `ROADMAP.md`)
- [ ] Wikis — disabled; documentation lives in `/docs`
- [x] Discussions — optional, enable when first external contributor lands

**Settings → Code security**

Available on every repository (enable now):

- [x] Dependency graph
- [x] Dependabot alerts
- [x] Dependabot security updates

GitHub Advanced Security (GHAS) features — free on **public** repos, paid on
private repos. Track and enable when the repository flips to public:

- [ ] Secret scanning *(GHAS-gated on private)*
- [ ] Push protection for secrets *(GHAS-gated on private; sub-toggle of Secret scanning)*
- [ ] Private vulnerability reporting *(GHAS-gated on private)*

### Private repo posture

`nightwatch` is private during incubation and will flip to public at or
before the M15 release. The three GHAS-gated features are intentionally
deferred — buying GHAS for a solo private repo is not in scope. The
consequences while private:

- Secrets committed to the repo are detected only after-the-fact, by Dependabot
  or by manual review. Treat every commit as if it could be made public
  tomorrow: no credentials, no signing identities, no provisioning profiles,
  no internal hostnames.
- The `gitleaks` CI check (PR #3) is the de-facto secret scanner until GHAS
  is available. It runs on every PR and is non-bypassable.
- Vulnerability reports from external researchers go through the contact in
  `SECURITY.md` until private vulnerability reporting is enabled.

When the repo goes public, enable all three GHAS features in the same
configuration pass and update this section.

---

## Branch protection — `main`

**Settings → Branches → Add branch protection rule**, pattern `main`.

| Rule | Setting |
|---|---|
| Require a pull request before merging | **On** |
| └ Require approvals | **1** |
| └ Dismiss stale approvals on new commits | **On** |
| └ Require review from Code Owners | **On** |
| Require status checks to pass | **On** (list maintained below) |
| └ Require branches to be up to date before merging | **On** |
| Require conversation resolution before merging | **On** |
| Require signed commits | **On** |
| Require linear history | **On** |
| Require deployments to succeed | Off (no deployment env yet) |
| Lock branch | Off |
| Do not allow bypassing the above settings | **On** — applies to admins too |
| Restrict who can push to matching branches | **On**, allow only: *no one* (PR-only) |
| Allow force pushes | **Off** |
| Allow deletions | **Off** |

### Solo-maintainer note

Until a second maintainer joins, the `Require approvals: 1` rule cannot be
satisfied by the author. Two workable options:

1. **Recommended:** keep the rule on; approve from a second GitHub identity
   tied to the same person (e.g., a personal account + a project bot account
   with `CODEOWNERS` membership). This preserves the audit trail and matches
   how the rule will work once the project has contributors.
2. **Acceptable short-term:** add the maintainer to a `Bypass list` for the
   "Require approvals" rule only, keeping every other protection on. Document
   the bypass in this file and remove it the moment a second maintainer
   joins.

Whichever path is chosen, **the bypass MUST be limited to the approval rule**.
Signed commits, linear history, status checks, and the no-force-push rule
apply to everyone, always.

### Required status checks

Status checks become required only after their workflow files exist on `main`
(otherwise PRs are blocked indefinitely waiting for a check that will never
run). Add each row below to the protected-branch required-checks list at the
milestone indicated.

| Check name | Workflow file | Required from |
|---|---|---|
| `build` | `.github/workflows/build.yml` | PR #3 (M0) |
| `test` | `.github/workflows/build.yml` (test job) | PR #3 (M0) |
| `lint` | `.github/workflows/lint.yml` | PR #3 (M0) |
| `codeql` | `.github/workflows/codeql.yml` | PR #3 (M0) |
| `gitleaks` | `.github/workflows/gitleaks.yml` | PR #3 (M0) |
| `rules-validate` | `.github/workflows/rules-validate.yml` | PR #3 (M0; no-op until M13) |
| `sign-check` | `.github/workflows/build.yml` (sign job) | M0 once a signed target exists (PR #4) |

---

## CODEOWNERS

`/.github/CODEOWNERS` declares review ownership. The file ships minimal at M0
(`* @xorxorjmp`) and expands per SPM module / app / extension as contributors
arrive. Update CODEOWNERS in the same PR that adds new ownership.

---

## Commit signing

Signed commits are required on `main`. Two supported methods:

1. **SSH signing** — recommended. Reuses the SSH key already configured for
   the `git@github.com:` remote and avoids a GPG dependency.
   ```bash
   git config --global gpg.format ssh
   git config --global user.signingkey ~/.ssh/id_ed25519.pub
   git config --global commit.gpgsign true
   git config --global tag.gpgsign true
   ```
   Then in **GitHub → Settings → SSH and GPG keys → New SSH key**, add the
   same public key with type **Signing Key**.

2. **GPG signing** — standard. Install `gpg`, generate a key, publish the
   public key to GitHub under SSH and GPG keys, and configure
   `commit.gpgsign true`.

CI must not skip signing (`--no-verify`, `--no-gpg-sign`) under any
circumstances.

---

## Current state (M0)

- Branch protection: applied in the GitHub UI after PR #2 merged. Required
  status checks remain unset until PR #3 (CI workflows) lands; see the
  Required status checks table above.
- Repo-level merge settings: applied (merge commits disabled, squash + rebase
  enabled, head branches auto-deleted).
- Commit signing: SSH signing via `~/.ssh/github_personal`, with the
  passphrase cached in the macOS Keychain via `ssh-add --apple-use-keychain`
  and `allowedSignersFile` configured for local verification. CI inherits
  signing through the contributor's commits; CI itself does not author
  commits.
- Repository visibility: **private during incubation.** See the Private repo
  posture subsection above. Flip to public at or before the M15 release and
  enable the three GHAS-gated Code Security features as part of that pass.
- Historical note: PRs #1 and #2 landed as merge commits because branch
  protection was applied between them and the "linear history" rule had not
  yet taken effect. Linear history applies from PR #3 onward.

---

## Verification checklist (after applying in the UI)

- [ ] Direct push to `main` is rejected with `protected branch hook declined`.
- [ ] PR with one unsigned commit is rejected with `commits must be signed`.
- [ ] PR with all required status checks not yet reporting cannot be merged.
- [ ] PR with a merge-commit history is rejected with `non-linear history`.
- [ ] Force-push to `main` is rejected.
- [ ] Branch deletion of `main` is rejected.
- [ ] A second-identity approval (or documented bypass) is required to merge.
