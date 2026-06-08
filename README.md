# model_driven_api

Part of the [Thecore framework](https://github.com/gabrieletassoni/thecore/tree/release/3).

A Rails engine that auto-generates a versioned REST API at `/api/v2/` by introspecting your ActiveRecord models at runtime. No per-model controllers or serializers needed — the schema drives everything.

## Features

- Full CRUD for every `ApplicationRecord` subclass with zero boilerplate
- Ransack-powered filtering and sorting (GET and POST)
- Pagination via Kaminari
- JWT authentication with sliding token expiration
- OAuth2 support: Google Workspace and Microsoft Entra ID
- LDAP / Active Directory authentication (via host app headers)
- Custom actions on any model — two patterns supported
- SELECT-only raw SQL endpoint
- Self-generated OpenAPI 3.0 / Swagger documentation
- `Content-Range` header for react-admin and similar frontends

---

## Installation

Add to your host app's `Gemfile`:

```ruby
gem 'model_driven_api', '~> 3.6'
```

Include the engine concerns in your host models:

```ruby
# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  include ModelDrivenApiApplicationRecord
end

# app/models/user.rb
class User < ApplicationRecord
  include ModelDrivenApiUser
end

# app/models/role.rb
class Role < ApplicationRecord
  include ModelDrivenApiRole
end
```

Run migrations:

```bash
bundle exec rails db:migrate
```

---

## Authentication

### JWT (email/password)

```http
POST /api/v2/authenticate
Content-Type: application/json

{ "auth": { "email": "admin@example.com", "password": "Change#1" } }
```

Response body: User JSON. Response header: `Token: <jwt>`.

Every subsequent authenticated request returns a fresh `Token` header (sliding expiration). Clients must read this header and store the new token on every response.

Token expiry is controlled by the `SESSION_TIMEOUT_IN_MINUTES` env var (default: 31 minutes).

When `ALLOW_MULTISESSIONS=false`, each login invalidates all previous tokens for the user (stored in the `used_tokens` table).

### Bearer token usage

```http
GET /api/v2/items
Authorization: Bearer <jwt>
```

---

## OAuth2 Authorization

OAuth2 is enabled when the relevant environment variables are set (see below). Two flows are supported:

### Server-side OmniAuth callback (traditional)

Set redirect URI to `http://yourdomain/auth/:provider/callback`. The OmniAuth middleware redirects to `/api/v2/auth/:provider/callback`, which returns the user JSON and a `Token` header.

### Frontend token exchange (`POST /api/v2/auth/jwt`)

For SPA frontends that obtain the OAuth token themselves:

```http
POST /api/v2/auth/jwt
Content-Type: application/json

{ "provider": "google", "provider_token": "<google-access-token>" }
```

The backend verifies the token against the provider's userinfo endpoint and returns a JWT.

### Register OAuth apps

#### Google

1. Go to [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials)
2. Create → OAuth 2.0 Client ID → Web Application
3. Add Authorized JavaScript Origins: your frontend URL
4. Note the Client ID

#### Microsoft Entra ID

1. Go to [portal.azure.com](https://portal.azure.com) → Microsoft Entra ID → App registrations → New registration
2. Set redirect URI type: SPA, value: your frontend URL
3. Note: Application (client) ID, Directory (tenant) ID
4. Under Authentication → Add platform: Single-page application

### Environment variables

```plaintext
# Microsoft
ENTRA_CLIENT_ID=your-client-id
ENTRA_CLIENT_SECRET=your-client-secret
ENTRA_TENANT_ID=your-tenant-id

# Google
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-client-secret

# JWT
SECRET_KEY_BASE=...
SESSION_TIMEOUT_IN_MINUTES=31

# Session mode: "false" enables token blacklisting
ALLOW_MULTISESSIONS=true
```

Frontend env vars (example for Vite):

```plaintext
VITE_GOOGLE_CLIENT_ID=your-client-id
VITE_AZURE_CLIENT_ID=your-client-id
VITE_AZURE_TENANT_ID=your-tenant-id
VITE_API_URL=http://yourdomain/api/v2/auth/google_oauth2/callback
```

---

## CRUD API

All `ApplicationRecord` subclasses get these endpoints automatically:

| Method | Path | Action |
|---|---|---|
| GET | `/api/v2/:model` | Index (all records or paginated) |
| GET | `/api/v2/:model/:id` | Show |
| POST | `/api/v2/:model` | Create |
| PUT / PATCH | `/api/v2/:model/:id` | Update |
| DELETE | `/api/v2/:model/:id` | Destroy |
| PUT / PATCH | `/api/v2/:model/:id/multi` | Bulk update (comma-separated ids) |
| DELETE | `/api/v2/:model/:id/multi` | Bulk destroy |
| POST | `/api/v2/:model/search` | Search (Ransack, same params as GET index) |

---

## Search, Filtering & Pagination

Parameters work identically in query string (GET) and JSON body (POST search).

### Pagination

| Param | Type | Effect |
|---|---|---|
| `page` | Integer | Page number |
| `per` | Integer | Records per page |
| `count` | any | Return `{ "count": N }` instead of records |

### Field selection (`a` or `json_attrs`)

```json
{
  "a": {
    "only": ["id", "name"],
    "methods": ["computed_field"],
    "include": { "items": { "only": ["id", "code"] } }
  }
}
```

### Ransack filtering (`q`)

```
q[field_predicate]=value
```

Common predicates: `_eq`, `_cont`, `_start`, `_end`, `_gt`, `_lt`, `_gteq`, `_lteq`, `_in`, `_present`, `_blank`.  
Sorting: `q[s]=field_name asc`.  
Cross-association: `q[user_email_end]=@example.com`.

### Examples

```
# Paginated index
GET /api/v2/users?page=2&per=10

# Filter + sort + field selection
GET /api/v2/orders?q[total_price_gt]=50&q[s]=created_at desc&a[only][]=id&a[only][]=total_price

# Count only
GET /api/v2/users?q[active_eq]=true&count=true

# Array filter
GET /api/v2/products?q[status_in][]=new&q[status_in][]=refurbished
```

POST equivalent (preferred for complex queries):

```http
POST /api/v2/orders/search
Authorization: Bearer <jwt>
Content-Type: application/json

{
  "q": { "total_price_gt": 50, "s": "created_at desc" },
  "a": { "only": ["id", "total_price"] }
}
```

The response includes a `Content-Range` header: `model_name start-end/total`.

---

## Custom Actions

### Pattern 1 — class method on the model

```ruby
class MyModel < ApplicationRecord
  # Called via: GET /api/v2/my_models?do=report
  def self.custom_action_report(params)
    [{ total: count, params: params }, 200]
  end

  # With record ID: GET /api/v2/my_models/:id?do=summary
  def self.custom_action_summary(params)
    [{ summary: "…" }, 200]
  end
end
```

### Pattern 2 — `NonCrudEndpoints` subclass (with OpenAPI docs)

Place in `app/models/endpoints/my_model.rb`:

```ruby
class Endpoints::MyModel < NonCrudEndpoints
  self.desc 'MyModel', :report, {
    get: {
      summary: "Monthly Report",
      tags: ["MyModel"],
      parameters: [
        { name: "month", in: "query", required: true, schema: { type: "integer" } }
      ],
      responses: {
        200 => { description: "Report data", content: { "application/json": { schema: { type: "object" } } } }
      }
    }
  }

  def report(params)
    [{ month: params[:month], data: [] }, 200]
  end
end
```

Routes for pattern 2:

```
GET    /api/v2/my_models/custom_action/report
GET    /api/v2/my_models/custom_action/report/:id
POST   /api/v2/my_models/custom_action/report
PUT    /api/v2/my_models/custom_action/report/:id
PATCH  /api/v2/my_models/custom_action/report/:id
DELETE /api/v2/my_models/custom_action/report/:id
```

---

## JSON Serialisation DSL (`json_attrs`)

Each model can declare `self.json_attrs` to control the API response shape. This mirrors the Rails `as_json` API.

```ruby
class MyModel < ApplicationRecord
  cattr_accessor :json_attrs
  self.json_attrs = {
    only: [:id, :name, :status],
    except: [:internal_notes],
    methods: [:computed_value],
    include: {
      category: { only: [:id, :name] },
      tags:     { only: [:id, :label] }
    }
  }
end
```

When composing `json_attrs` across multiple concerns, use `ModelDrivenApi.smart_merge` to deep-merge without losing fields set by other concerns:

```ruby
self.json_attrs = ModelDrivenApi.smart_merge((json_attrs || {}), { only: [:id, :name] })
```

Clients can override the shape per-request via the `a` or `json_attrs` query/body parameter.

---

## Raw SQL endpoint

Executes read-only SELECT queries. The query **must** return a `result` key (use `json_agg`).

```http
POST /api/v2/raw/sql
Authorization: Bearer <jwt>
Content-Type: application/json

{
  "query": "SELECT json_agg(u) AS result FROM users u WHERE u.admin = true"
}
```

Only `SELECT` (and `WITH … SELECT`) statements are allowed. DDL and DML are rejected with HTTP 400.

Complex example with CTE:

```sql
WITH data AS (
  SELECT u.id, u.email, json_agg(r.name) AS roles
  FROM users u
  JOIN users_roles ur ON ur.user_id = u.id
  JOIN roles r ON r.id = ur.role_id
  GROUP BY u.id
)
SELECT jsonb_agg(data) AS result FROM data;
```

---

## Info endpoints

All under `/api/v2/info/` (authenticated except where noted):

| Endpoint | Auth | Description |
|---|---|---|
| `GET /info/version` | No | App version string |
| `GET /info/heartbeat` | Yes | Renews token, returns current user |
| `GET /info/ntp` | Yes | Server UTC time (client clock sync) |
| `GET /info/roles` | Yes | All roles |
| `GET /info/schema` | Yes | DB schema for models the user can read |
| `GET /info/dsl` | Yes | `json_attrs` DSL for each model |
| `GET /info/translations` | Yes | Full i18n tree (`?locale=en`) |
| `GET /info/settings` | Yes | All `ThecoreSettings::Setting` values |
| `GET /info/swagger` | No | OpenAPI 3.0 spec (alias: `/info/openapi`) |

---

## ActiveStorage file uploads

For models with `has_many_attached :assets`, use `multipart/form-data` — do not use JSON:

```javascript
const formData = new FormData();
formData.append('product[title]', title);
files.forEach(file => formData.append('product[assets][]', file));

// Do NOT set Content-Type manually — the browser sets the boundary
fetch('/api/v2/products', { method: 'POST', body: formData });
```

To delete attachments, pass the `ActiveStorage::Attachment` IDs via a virtual attribute:

```javascript
idsToRemove.forEach(id => formData.append('product[remove_assets][]', id));
fetch(`/api/v2/products/${id}`, { method: 'PATCH', body: formData });
```

---

## License

MIT
