# Generate named serializer classes lazily from json_attrs

API v3 uses `jsonapi-serializer`, which normally requires a hand-written serializer class per model. To preserve zero-boilerplate auto-generation, the engine defines `Api::V3::ModelSerializer` the first time a Resource is serialized, building it from the Resource's `json_attrs`. The class is assigned under a named constant so it is cacheable and inspectable. Host apps can override by defining the class before the first request — the factory checks for an existing constant before generating.

## Consequences

Serializer classes do not exist at boot — they appear on first request. Code that introspects `ObjectSpace` or eager-loads serializer constants at startup will not find them.
