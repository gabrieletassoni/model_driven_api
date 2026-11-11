# Security scanning

> Moved verbatim from `CLAUDE.md` on 2026-11-11 (CodeQL, secret scanning, Dependabot, brakeman.ignore). `CLAUDE.md` points here; keep this file accurate whenever the behaviour it describes changes.

Configured in the GitHub repository settings, not in files:

- **CodeQL** default setup (Ruby, the Actions workflows, and JavaScript/TypeScript where the gem
  ships any): on every push to `release/3`, on pull requests and weekly. Findings: Security → Code
  scanning.
- **Secret scanning with push protection**: a push containing a recognised secret is rejected. It
  is the only check that blocks anything. If it fires on a real secret, remove it from the commit and
  rotate the secret; never bypass it.
- **Dependabot alerts and security updates**, but no `dependabot.yml`, so no routine version-bump
  pull requests. This gem commits no `Gemfile.lock`, so Dependabot only sees the gemspec and the
  workflow Actions: CVEs in the resolved Ruby dependencies are caught by `bundler-audit` in the host
  apps' pipelines, whose `Gemfile.lock` resolves every ATOM.
- Findings never block a release: GitHub notifies the owner. When one needs work, open a GitHub
  issue (see the Agent skills section of `CLAUDE.md`).
- `config/brakeman.ignore` (for a local `brakeman` run) records the High `UnsafeReflection` in
  `public_custom_action?` as a false positive (see `docs/agents/custom-actions.md`). Each entry's `note` says why.
