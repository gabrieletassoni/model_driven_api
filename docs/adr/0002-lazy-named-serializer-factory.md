# Generate named serializer classes lazily from json_attrs

API v3 uses `jsonapi-serializer`, which normally requires a hand-written serializer class per model. To preserve zero-boilerplate auto-generation, the engine defines `Api::V3::ModelSerializer` the first time a Resource is serialized, building it from the Resource's `json_attrs`. The class is assigned under a named constant so it is cacheable and inspectable. Host apps can override by defining the class before the first request — the factory checks for an existing constant before generating.

All four `json_attrs` keys are supported:
- `only:` / `except:` — column attribute list (resolved once by `Api::ResourceAttributeSet.for`)
- `methods:` — virtual attributes; each becomes a block-form `attribute` calling `object.send(method_name)`. `send` (not `public_send`) is required because `thecore_backend_commons` injects private methods into every model.
- `include:` — each association entry generates a nested serializer (`<AssocModel>For<ParentModel>Serializer`) registered with the correct macro from `reflect_on_all_associations`. Nesting is flat (one level only) to prevent infinite loops on circular associations.

## Consequences

Serializer classes do not exist at boot — they appear on first request. Code that introspects `ObjectSpace` or eager-loads serializer constants at startup will not find them. Nested serializers are also lazily cached; changes to `json_attrs` at runtime are not reflected until the process restarts.
