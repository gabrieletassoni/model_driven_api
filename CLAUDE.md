# CLAUDE.md — model_driven_api

This is a Rails engine gem (`model_driven_api`) that auto-generates a versioned REST API at `/api/v2/` (plain JSON, Ransack-powered) and `/api/v3/` (JSON:API-compliant) by introspecting ActiveRecord models at runtime. It lives as a git submodule inside a parent Thecore application.

Every request goes through `Api::V2::ApplicationController` (v3 inherits it): JWT auth, model resolution, CanCan authorization, CRUD. Public gem on GitHub; `.github/workflows/gempush.yml` publishes to RubyGems only when `lib/model_driven_api/version.rb` changes on `release/3`.

## Where things are

```
app/controllers/api/v2/  application (core CRUD + auth), authentication, auth/oauth, info, raw (SQL)
app/controllers/api/v3/  JSON:API layer on v2: application, authentication, auth/oauth, info, raw, users
app/models/endpoints/    push_subscriber.rb (custom endpoints)
lib/model_driven_api.rb  gem entrypoint (explicit requires: pagy, jsonapi/serializer)
lib/model_driven_api/    engine.rb, version.rb
lib/api/                 model_resolver, custom_action_dispatcher, resource_attribute_set,
                         open_api/{base,v2,v3}, v3/serializer_factory
lib/                     json_web_token.rb, safe_sql_executor.rb, non_crud_endpoints.rb, concerns/
config/initializers/     after_initialize_for_model_driven_api.rb, default_json_attrs_registration.rb
spec/  test/dummy/       RSpec + PostgreSQL dummy app
docs/adr/  docs/agents/  GLOSSARY.md  AGENTS.md (orientation map)
```

## Read before working on…

| Topic | File |
| --- | --- |
| Entry point, v2/v3 controllers and request flow, Ransack search, routes | `docs/agents/request-pipeline.md` |
| `json_attrs`, `SerializerFactory`, host-model concerns, default `json_attrs` | `docs/agents/serialization.md` |
| Custom actions (`?do=`, `NonCrudEndpoints`, `public_action`), PushSubscriber endpoints | `docs/agents/custom-actions.md` |
| JWT and key rotation, raw SQL, `info/version`, OpenAPI generation | `docs/agents/jwt-raw-sql-info-openapi.md` |
| Key invariants and gotchas (full text of the rules below) | `docs/agents/invariants-and-gotchas.md` |
| Dummy app, schema, spec helpers | `docs/agents/testing.md` |
| CodeQL, secret scanning, Dependabot, `brakeman.ignore` | `docs/agents/security-scanning.md` |
| Issues (GitHub), triage labels, glossary/ADR layout | `docs/agents/issue-tracker.md`, `triage-labels.md`, `domain.md` |

## Commands

```bash
# Run specs (from inside the submodule directory)
bundle exec rspec

# Lint
bundle exec standardrb

# Release a new version:
# 1. Bump lib/model_driven_api/version.rb
# 2. Commit and push — CI builds the gem
```

Tests run on PostgreSQL only, never SQLite. First run: `cd test/dummy && RAILS_ENV=test bundle exec rails db:create`.

## Rules most tasks need

- **UTC-only backend, enforced at boot** (`ModelDrivenApi.enforce_utc!`). Never reintroduce a global `as_json` override on time classes.
- `params` is `request.parameters`: never use `params.require(...).permit(...)`.
- `update` and `patch` are the same method.
- Every runtime dependency needed at class-body evaluation (`pagy`, `jsonapi/serializer`) is `require`d explicitly in `lib/model_driven_api.rb`; add any new runtime dependency's constant to `spec/lib/self_contained_require_spec.rb`.
- `Api::ResourceAttributeSet.for(model)` is the single source of truth for `json_attrs[:only/:except/:methods/:include]`: never inline it. Compose `json_attrs` with `ModelDrivenApi.smart_merge`, never plain `merge`.
- `SerializerFactory` uses `send`, not `public_send`, for `methods:`, and caches serializers per class until restart.
- OpenAPI paths live in `Api::OpenApi::V2/V3`, not in the info controllers.
- `extract_model` never instantiates the class named by the request path.
- Public custom actions (`public_action`) skip JWT and CanCan; `params[:current_user_id]` is nil there.
- Custom-action and v3 raw SQL responses are plain JSON, never JSON:API envelopes.
- v2 index on an empty collection answers 404 with `[]` (unless `always_ok=true`): a contract, don't change it.
- `ApiExceptionManagement` handlers are production-only; the `StandardError` catch-all is declared **first**. Never map `NoMethodError`.
- `append_migrations` compares roots with `==`, never `.match`.
- **Never add host-app models or tables to the dummy app**; regenerate its schema from the dependency chain.
- Secret scanning push protection: if it fires on a real secret, remove it and rotate; never bypass it.
- Keep this file or the `docs/agents/` file it points to accurate whenever the behaviour it describes changes.

## Agent skills

### Issue tracker

Tasks, issues, bugs, tickets and specs for this repository live **only** in its GitHub Issues
(`gabrieletassoni/model_driven_api`), handled with the `gh` CLI. See `docs/agents/issue-tracker.md`.

**Mandatory rule.** Whenever a skill or development work creates, reads, updates, comments on,
assigns, blocks or closes a task, issue, bug, ticket or spec (for example /to-tickets, /to-spec,
/triage, /wayfinder, /implement, /diagnosing-bugs, /code-review, closing a piece of work, a bug found
during a session), do it in this repository's GitHub Issues following `docs/agents/issue-tracker.md`.
Never use Odoo, `.scratch/` or local Markdown files as a tracker: Odoo is only for the repositories
on Bancolini's GitLab. `#123` means a GitHub issue number of this repository. If `gh` doesn't work,
stop and say so instead of falling back to another tracker.

### Triage labels

The five canonical triage roles map to GitHub labels with the same name (`needs-triage`,
`needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root, created lazily when the first
term or decision is resolved. See `docs/agents/domain.md`.

### Skills

Matt Pocock's skills come from the `mattpocock-skills` Claude Code plugin installed on the
developer's **host** (`claude plugins install mattpocock-skills`, official marketplace), never
vendored here: no `.agents/skills/`, `.claude/commands/` or `skills-lock.json`. Its `ask-matt` skill
maps how the skills connect.
