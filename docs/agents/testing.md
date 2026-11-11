# Test infrastructure

> Moved verbatim from `CLAUDE.md` on 2026-11-11 (dummy app, schema, spec_helper, factories, has_rich_text stub). `CLAUDE.md` points here; keep this file accurate whenever the behaviour it describes changes.

The dummy app (`test/dummy/`) isolates the engine from host-app concerns. It runs on PostgreSQL (the only DB target — never SQLite): `test/dummy/config/boot.rb` keeps `DATABASE_URL`'s server/credentials but always swaps in `model_driven_api_<env>` as the database, because `DATABASE_URL` overrides `database.yml` and in the devcontainer points at the host app's dev DB — which `spec_helper`'s `load` of the dummy `schema.rb` (`force: :cascade`) would otherwise silently recreate table by table. First run: `cd test/dummy && RAILS_ENV=test bundle exec rails db:create`. Its schema is derived from the dependency chain — **never add host-app models or tables to the dummy app**.

- `test/dummy/db/schema.rb` — generated from the dependency chain migrations: `thecore_auth_commons` (users, roles, role_users, permissions chain, ldap_servers), `thecore_settings`, this gem's `used_tokens`, and `active_storage` tables (required because `rails/all` registers ActiveStorage `before_destroy` callbacks on `ActiveRecord::Base`). Regenerate with: `RAILS_ENV=test bundle exec rake db:migrate db:schema:dump` from the engine root.
- `spec/spec_helper.rb` — loads schema via `load`, sets `SECRET_KEY_BASE`, requires `bcrypt`, patches `Ability#initialize` in `before(:suite)` to grant `can :manage, :all`. Permissions tables exist but are empty in tests; without this patch the user would have no abilities.
- `test/dummy/config/application.rb` — stubs `action_mailbox`, `action_mailer`, `action_cable`, `assets` on `Rails::Application::Configuration`; adds dummy autoload paths; stubs `has_rich_text` (see below); pre-requires stub models before engine hooks fire.
- `spec/factories/users.rb` — uses `BCrypt::Password.create(...)` directly (no Devise).
- `spec/factories/roles.rb` — Role factory; `spec/requests/api/v3/roles_spec.rb` is the v3 integration test (26 tests against `Role`, the canonical model from `thecore_auth_commons`).

**`has_rich_text` stub** — the dummy app stubs ActionText's `has_rich_text` macro via an `ActiveSupport.on_load(:active_record)` block. The stub must actually define the named instance method (returning `nil`) so that `rich_content_html` (injected by `thecore_backend_commons`) can call `rich_content` without raising `NoMethodError`. A no-op `def has_rich_text(*); end` is insufficient.

```ruby
# test/dummy/config/application.rb — correct stub
extend(Module.new do
  def has_rich_text(*names)
    names.each { |name| define_method(name) { nil } }
  end
end) unless respond_to?(:has_rich_text)
```
