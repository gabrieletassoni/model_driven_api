# model_driven_api

A Rails engine that auto-generates a versioned REST API by introspecting ActiveRecord models at runtime. Host apps get a full CRUD + auth API with zero per-model boilerplate.

## Language

### API surface

**Resource**:
An ActiveRecord model exposed through the auto-generated API. The engine discovers Resources at runtime — no explicit registration required.
_Avoid_: endpoint, entity, object

**json_attrs**:
A class-level hash on a Resource model (keys: `:only`, `:except`, `:methods`, `:include`) that controls which attributes and associations are serialized. Clients can override it per-request via the `a` or `json_attrs` query param.
_Avoid_: serialization config, field whitelist

**SQL Escape Hatch**:
A GET and POST endpoint (`/api/vN/raw/sql`) that executes a caller-supplied SELECT query directly against the database, bypassing the Resource abstraction. Used when ActiveRecord-generated queries are insufficient for performance-critical reads. Authentication required; write operations are rejected. Returns plain JSON in both API v2 and API v3 — a deliberate exception to JSON:API compliance in v3.
_Avoid_: raw endpoint, raw SQL endpoint, direct SQL

**Custom Action**:
A non-CRUD operation attached to a Resource, declared either as a class method (`Model.custom_action_foo`) or via a `NonCrudEndpoints` subclass. Custom Actions are escape-hatch territory; they return plain JSON, not a JSON:API envelope.
_Avoid_: custom endpoint, action, hook

**NonCrudEndpoints**:
A base class (`< NonCrudEndpoints`) for grouping Custom Actions per Resource in `app/models/endpoints/`. One subclass per Resource, placed in the host app.
_Avoid_: endpoint class, action class

### API versioning

**API v2**:
The existing auto-generated REST API at `/api/v2/`. Uses plain JSON responses, Ransack for filtering, and `json_attrs` for serialization shape.

**API v3**:
The JSON:API-compliant API at `/api/v3/`. Shares auth and authz with v2 but uses JSON:API response envelopes, a Serializer Factory, and JSON:API-native query params (filter/sort/page).
_Avoid_: new API, v3 API

### Serialization

**Serializer Factory**:
The engine mechanism that generates a named `Api::V3::ModelSerializer` class lazily on first request, derived from the Resource's `json_attrs`. Host apps can override by defining the class explicitly before first request.
_Avoid_: auto-serializer, dynamic serializer

### Querying

**JSON:API-native params**:
The query parameter conventions used in API v3: `?filter[field]=value` for filtering, `?sort=field,-other` for ordering, `?page[number]=N&page[size]=N` for pagination. Filter fields are validated against the Resource's `ransackable_attributes` whitelist.
_Avoid_: JSON:API query params, v3 params

### Deep modules (architectural)

**ResourceAttributeSet**:
A value object (`Struct`) that resolves a Resource's `json_attrs` (`only:`/`except:`/`methods:`/`include:`) into a single named struct. Created via `Api::ResourceAttributeSet.for(model_class)`. The single source of truth for attribute resolution — used by both the Serializer Factory and the OpenAPI generator.
_Avoid_: attribute config, field resolver

**ModelResolver**:
A plain Ruby class (`Api::ModelResolver`) that resolves the `@model` constant from request params. Raises `Api::ModelResolver::NotFound` when a class is found but is not an ActiveRecord model. Returns `nil` (no exception) when no class can be resolved — allowing model-less controllers (e.g. info endpoints) to continue.
_Avoid_: model lookup, controller model extraction

**CustomActionDispatcher**:
A plain Ruby class (`Api::CustomActionDispatcher`) that detects and dispatches Custom Action requests (`?do=` or `/custom_action/` URL patterns) from both v2 and v3 controllers. Returns `false` when no Custom Action is detected, or `[true, body, status]` when dispatched. Bearer tokens are read from the `Authorization` header only.
_Avoid_: custom action handler, action dispatcher

**OpenApiGenerator**:
A family of plain Ruby classes (`Api::OpenApi::Base`, `V2`, `V3`) that generate OpenAPI 3.0 path objects. `Base` holds shared type helpers. `V2#generate` produces v2-accurate paths; `V3#generate` produces v3-accurate paths with JSON:API schemas. Called from the info controllers — the controllers own the outer spec envelope, the generators own the paths.
_Avoid_: swagger generator, OpenAPI builder
