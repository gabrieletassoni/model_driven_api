# Serialization options from the request follow conventions, not lists

API v2 lets a client send `as_json` options (`a`, alias `json_attrs`) that replace the model's own `json_attrs`. Rails runs `send` on every `methods` name and every `include` key, so a user who could only read a model could call any public method of its records from a GET (`destroy` included), and `only` brought back attributes the model hides (Devise leaves `encrypted_password` out with `except`, which `only` overrides). Host Odoo #6285.

The fix had to be secure, zero maintenance in every Thecore backend, and backward compatible with every frontend that reads fields through `a` today, without an inventory of what they send.

## Decision

Options that come from the request are marked (`Api::V2::RequestJsonAttrs::MARK`) and every record (or ActiveModel object a custom action returns) serializes them with the rules of its own class (a module prepended to `ActiveModel::Serialization#serializable_hash`):

- `include` keeps real associations only; `AutoIncludeJson` preloads only those.
- Secrets the class hides never come back, through `only`, `methods` or `except`: columns whose name is a secret's by Rails' `filter_parameters` convention (`passw`, `token`, `secret`, `crypt`, `salt`, `_key`, ...) and that the class hides through its default `serializable_hash`, its own `json_attrs[:except]` or `write_only_attributes` (`Api::HiddenSecrets`). Other hidden columns (Devise's sign-in times, counts and IPs) are still served through `only`, as frontends read them today.
- A `methods` name the class declares in `json_attrs[:methods]` runs as before: a developer exposed it, side effects included.
- A column, an association or `<association>_ids` is a plain read.
- Any other name must be public, not a callback of the class (host Odoo #6314), end in neither `!` nor `=`, take no required argument, and be written in the host app or in a thecore gem (named `thecore*` or depending on one). The gem that owns the file decides before the app's root does: deploy images install the bundle inside the app (`/app/vendor/bundle`). It runs under `ActiveRecord::Base.while_preventing_writes`; if it writes or raises, the record's attributes are restored and only that field is dropped.
- A dropped name is logged once per request (`ModelDrivenApi::Current`); the response stays 200.

Options built by the code (a model's `json_attrs`, a custom action's `@json_attrs`) are not marked and behave as before.

## Considered options

- **Allowlist of requestable names per model**: rejected. Every backend would have to maintain it and every frontend would first have to list what it sends; a missed name breaks a customer's production.
- **Denylist by name** (`!`, `=`, ActiveRecord and Object methods): not enough alone. Methods mixed in by gems (Devise's `authenticatable_salt` returns the hash's salt) and public callbacks written by us pass it.
- **Conventions derived from what the code already states** (where a method is written, what `json_attrs` declares, what `serializable_hash` hides): chosen. New models and gems are covered with no edit.

## Consequences

- Classification is cached per class and method name (only names the class defines, so client-chosen names cannot grow it), hidden attributes per class, gem roots once: on 300 records the rules cost about 0.4 ms per response, the guard a few microseconds per record and method.
- Side effects that never touch the database (an e-mail sent with `deliver_now`, an HTTP call) are not blocked by the guard: an undeclared method of ours must not have them. Methods that should never be reachable belong in `private`.
- A frontend that needs a framework method or a writer must have it declared in the model's `json_attrs[:methods]`.

## Extension: the same secrets everywhere (host Odoo #6313, 3.19.0)

The secrets of the first point were still readable by other paths: v3 serialized `encrypted_password` in every User response (`ResourceAttributeSet` reads `json_attrs`, not Devise's `serializable_hash`), Ransack filtered and sorted on every column (`q[encrypted_password_start]` rebuilt the hash a character at a time), v3 `sort` ordered by any column, and a secret hidden only through `json_attrs[:except]` (`encrypted_access_token`) came back with `a[only]`. `Api::HiddenSecrets.for(model)` is now the one list, used by v3 attributes, v2 request options and the default `ransackable_attributes`; v3 `sort` takes only `ransortable_attributes`. A secret-named column the model doesn't hide stays readable.

## Extension: callbacks are lifecycle, not API (host Odoo #6314, 3.20.0)

Public callbacks written by us (`before_validation :set_site_from_project`, `after_save :reload_schedules`) passed every rule: public, ours, no arguments. The read-only guard stops the ones that write to the database, but not one whose effect lives outside it (`reload_schedules` rewrites the Sidekiq cron in Redis). A name registered as a Symbol filter in any of the record class's callback chains (`__callbacks`: validation, validate, save, create, update, destroy, commit, rollback, initialize, find, touch, custom ones) is now refused with reason `a callback`, unless the class declares it in `json_attrs[:methods]`. Proc and object callbacks have no name a client could send. The ATOMs also made their six public callbacks `private` (mytask, thecore_background_jobs, thecore_auth_commons): the rule covers the ones a gem forgets.
