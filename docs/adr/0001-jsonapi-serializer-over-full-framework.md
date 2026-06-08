# Use jsonapi-serializer over a full JSON:API framework for API v3

API v3 needs JSON:API-compliant responses. The two full-framework alternatives — `jsonapi-resources` and `Graphiti` — both require a hand-declared Resource class per model, which directly contradicts the engine's core value of zero per-model boilerplate. We chose `jsonapi-serializer` (serializer layer only) so the engine retains full control over model introspection, filtering, and routing, while getting the JSON:API response envelope for free.

## Considered Options

- **jsonapi-resources** — full framework, auto-wires routes; rejected because it demands an explicit `Resource` class per model, breaking auto-generation.
- **Graphiti** — richer querying and a front-end toolkit; rejected for the same reason, plus a smaller community.
- **jsonapi-serializer** — serializer only; chosen because it handles the envelope without imposing a resource-declaration model.
