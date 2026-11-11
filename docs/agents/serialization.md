# Serialization (json_attrs, SerializerFactory, model concerns)

> Moved verbatim from `CLAUDE.md` on 2026-11-11 (v3 SerializerFactory, concerns for host models, default json_attrs, json_attrs DSL). `CLAUDE.md` points here; keep this file accurate whenever the behaviour it describes changes.

## `Api::V3::SerializerFactory` (`lib/api/v3/serializer_factory.rb`)

Lazily generates a named `JSONAPI::Serializer` subclass from each model's `json_attrs`. Classes are cached in the `Api::V3` namespace as `<ModelName>Serializer` after first generation.

Attribute resolution is delegated to `Api::ResourceAttributeSet.for(model_class, jattrs:)` (see `docs/agents/invariants-and-gotchas.md`), which owns the `only:` / `except:` / `methods:` / `include:` logic in one place. The factory reads the resolved struct fields directly.

`json_attrs[:methods]` — each symbol becomes a block-form `attribute` using `object.send(method_name)`. `send` (not `public_send`) is required — `thecore_backend_commons`'s `BaseApplicationRecordConcern` injects `methods: [:assets_paths, :rich_content_html]` into every model at `after_initialize` time, and both are declared `private`. Rails `as_json` uses `send` for the same reason.

`json_attrs[:include]` — each entry is a bare symbol (`:assoc`) or a hash (`assoc: { only: [:id] }`). A nested serializer is generated as `<AssocModel>For<ParentModel>Serializer`, registered with the correct macro (`has_many`/`has_one`/`belongs_to`) from `reflect_on_all_associations`. Nested serializers are always flat — `include:` is not processed recursively — to prevent infinite loops on circular associations (e.g. `Role ↔ User`).

`extract_includes(include_spec)` is still a public class method (specs test it directly); it delegates to `Api::ResourceAttributeSet#parsed_includes`.

```ruby
serializer = Api::V3::SerializerFactory.serializer_for(Role)
# → Api::V3::RoleSerializer (generated on first call, cached afterwards)
# Also generates Api::V3::UserForRoleSerializer when Role.json_attrs[:include] contains users:
```

The `:id` field is excluded from `attributes` (the serializer handles it as the resource identifier). When all non-id attributes are stripped, the jsonapi-serializer gem omits the `:attributes` key entirely from the hash (per JSON:API spec). Use `.to_h` when asserting emptiness: `expect(attrs.to_h).to be_empty`.

## Concerns to include in host models

| Concern | Include in | Purpose |
|---|---|---|
| `ModelDrivenApiApplicationRecord` | `ApplicationRecord` | Enables `ransackable_attributes` / `ransackable_associations` |
| `ModelDrivenApiUser` | `User` | Adds `has_many :used_tokens`, default `json_attrs` |
| `ModelDrivenApiRole` | `Role` | Adds default `json_attrs` |
| `ModelDrivenApiPushSubscriber` | `PushSubscriber` | `json_attrs` includes `user: { only: [:id, :email, :name, :surname] }` |
| `ModelDrivenApiPushMessage` | `PushMessage` | `json_attrs` includes `sender: { only: [:id, :email, :name, :surname] }` |

All concerns are registered in `config/initializers/after_initialize_for_model_driven_api.rb` via `send(:include, ...)` inside `after_initialize`. New model concerns go in `lib/concerns/` following the `ModelDrivenApi<ModelName>` naming convention.

## Default `json_attrs` for every model (`ModelDrivenApiDefaultJsonAttrs`, ADR 0001)

Per `vendor/external/thecore/docs/adr/0001-application-record-defaults-over-generated-concerns.md` (host app), a model does **not** need a generated `Api::ModelName` concern just to get a working default API serialization shape. `lib/concerns/model_driven_api_default_json_attrs.rb` defines `ModelDrivenApiDefaultJsonAttrs` — an `ActiveSupport::Concern` whose `included do` block sets `self.json_attrs = { except: [] }` (all columns, no `methods`, no `include`d associations) via `cattr_accessor`, same as the named concerns above.

It is registered once, in `config/initializers/default_json_attrs_registration.rb`, into `ThecoreBackendCommons::DefaultModuleRegistry`:

```ruby
ThecoreBackendCommons::DefaultModuleRegistry.register(ModelDrivenApiDefaultJsonAttrs)
```

with no `applies_to:` (defaults to every `ApplicationRecord` subclass). The registry `include`s it into each subclass from `ApplicationRecord.inherited`, at the moment the subclass is defined — installed from `config.to_prepare`, not `after_initialize`, so it is in place before eager loading (see the registry's own docs in `thecore_backend_commons`'s `CLAUDE.md`/`lib/thecore_backend_commons/default_module_registry.rb`).

This composes safely with an explicit `Api::ModelName` concern (host-app convention) or with the named concerns above: `ApplicationRecord.inherited` fires *before* the subclass's own body executes, so the default is always applied first and the class body's later `include Api::ModelName` (or `include ModelDrivenApiUser`/`ModelDrivenApiRole`) always runs after — freely overriding, or (via `ModelDrivenApi.smart_merge`) merging on top of, the default's `{ except: [] }`, which is a no-op when merged (an empty array extended with a non-empty one is just the non-empty one). Models with an explicit concern are therefore unaffected; only a model with no concern at all keeps the bare default. Abstract/STI classes are excluded exactly as the registry itself guarantees (`apply_to` is a no-op for `klass.abstract_class?`, and an STI child inherits the module from its base rather than being re-included).

This required `ThecoreBackendCommons::DefaultModuleRegistry`, which shipped in `thecore_backend_commons` 3.5.0 — the gemspec's existing `~> 3.0` constraint resolves it normally from RubyGems, no pin needed (a temporary `git:`-sourced pin lived in `Gemfile` for a while before 3.5.0 was published and its RubyGems index propagated; it's gone now).

Covered by `spec/initializers/default_json_attrs_spec.rb` — default applied to a no-concern model (`RoleUser`), `instance_methods(false).include?(:json_attrs)`, an explicit-concern model (`Role`) unaffected, abstract-class exclusion, and both `/api/v2/info/schema` and `/api/v2/info/dsl` actually surfacing the default-only model (a previously untested path).

## JSON serialisation DSL (`json_attrs`)

Each model exposes `self.json_attrs` as a class-level hash with the standard Rails `as_json` keys: `:only`, `:except`, `:methods`, `:include`. The engine reads this in every v2 CRUD response. The v3 `SerializerFactory` reads `json_attrs[:only]` first, then falls back to `column_names - [:except]` if `only:` is not set. Clients can override the shape per-request via the `a` or `json_attrs` query parameter (v2 only).

Use `ModelDrivenApi.smart_merge(existing, additions)` when composing `json_attrs` across concerns — it does a deep merge that extends arrays rather than replacing them. Since 3.11.3 it delegates to `ThecoreBackendCommons.smart_merge` (thecore_backend_commons >= 3.8), where the implementation now lives so lower-layer gems (thecore_backend_commons itself, thecore_ui_rails_admin) can use it without referencing this gem; in those gems call `ThecoreBackendCommons.smart_merge` directly.
