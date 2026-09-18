# model_driven_api

Part of the [Thecore framework](https://github.com/gabrieletassoni/thecore/tree/release/3).

A Rails engine that auto-generates a versioned REST API by introspecting your ActiveRecord models at runtime. No per-model controllers or serializers needed — the schema drives everything.

| Version | Base path | Format | Query style |
|---|---|---|---|
| v2 | `/api/v2/` | Plain JSON | Ransack predicates (`q[field_eq]=value`) |
| v3 | `/api/v3/` | JSON:API | `filter[field]=value`, `sort=field`, `page[number]=N` |

---

## Features

- Full CRUD for every `ApplicationRecord` subclass with zero boilerplate
- **v2**: Ransack-powered filtering and sorting (GET and POST search endpoint)
- **v3**: JSON:API-compliant envelopes; filter/sort/page query params; Pagy pagination
- JWT authentication with sliding token expiration (shared by v2 and v3)
- OAuth2 support: Google Workspace and Microsoft Entra ID
- LDAP / Active Directory authentication (via host app headers)
- Custom actions on any model — two patterns supported (v2 and v3)
- SELECT-only raw SQL endpoint (v2 and v3)
- Self-generated OpenAPI 3.0 / Swagger documentation (v2 and v3)
- JSON:API sideloading with hybrid defaults (`json_attrs[:include]` + `?include=` override)
- JSON:API sparse fieldsets (`?fields[type]=f1,f2`)
- `Content-Range` header for react-admin and similar frontends (v2)

---

## Installation

Add to your host app's `Gemfile`:

```ruby
gem 'model_driven_api', '~> 3.6'
```

The gem declares `pagy ~> 9.0` as a runtime dependency and explicitly requires it at load time. No additional configuration is needed for pagination to work.

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

### Bearer token usage (v2 and v3)

```http
GET /api/v2/items
Authorization: Bearer <jwt>

GET /api/v3/items
Authorization: Bearer <jwt>
Accept: application/vnd.api+json
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

## API v2 — Plain JSON (Ransack)

### CRUD endpoints

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

### Search, filtering & pagination

Parameters work identically in query string (GET) and JSON body (POST search).

#### Pagination

| Param | Type | Effect |
|---|---|---|
| `page` | Integer | Page number |
| `per` | Integer | Records per page |
| `count` | any | Return `{ "count": N }` instead of records |

#### Field selection (`a` or `json_attrs`)

```json
{
  "a": {
    "only": ["id", "name"],
    "methods": ["computed_field"],
    "include": { "items": { "only": ["id", "code"] } }
  }
}
```

#### Ransack filtering (`q`)

```
q[field_predicate]=value
```

Common predicates: `_eq`, `_cont`, `_start`, `_end`, `_gt`, `_lt`, `_gteq`, `_lteq`, `_in`, `_present`, `_blank`.  
Sorting: `q[s]=field_name asc`.  
Cross-association: `q[user_email_end]=@example.com`.

#### Examples

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

## API v3 — JSON:API

All responses follow the [JSON:API 1.0](https://jsonapi.org) specification. Send `Accept: application/vnd.api+json` and `Content-Type: application/vnd.api+json` on write requests.

### CRUD endpoints

| Method | Path | Action | Response |
|---|---|---|---|
| GET | `/api/v3/:model` | Index | `{ data: […], meta: { total: N } }` |
| GET | `/api/v3/:model/:id` | Show | `{ data: { id, type, attributes } }` |
| POST | `/api/v3/:model` | Create | `{ data: { … } }` — 201 Created |
| PATCH | `/api/v3/:model/:id` | Update | `{ data: { … } }` — 200 OK |
| DELETE | `/api/v3/:model/:id` | Destroy | 204 No Content |

### Filtering

```
GET /api/v3/articles?filter[title]=Hello
GET /api/v3/articles?filter[status]=published&filter[author_id]=42
```

Field names are validated against the model's `ransackable_attributes` whitelist. Unknown fields are silently ignored.

### Sorting

```
GET /api/v3/articles?sort=title           # ascending
GET /api/v3/articles?sort=-created_at     # descending
GET /api/v3/articles?sort=status,-title   # multi-field
```

### Pagination

```
GET /api/v3/articles?page[number]=2&page[size]=10
```

Response includes `meta.total` with the full count:

```json
{
  "data": [ … ],
  "meta": { "total": 47 }
}
```

### Sparse fieldsets

Return only a subset of attributes per type:

```
GET /api/v3/articles?fields[articles]=title,published_at
```

Multiple types can be narrowed in a single request when sideloading:

```
GET /api/v3/roles/1?include=users&fields[roles]=name&fields[users]=email
```

### Sideloading (relationships)

Default sideloads are defined in the model's `json_attrs[:include]`. The client can override:

```
# Default sideloads from json_attrs[:include]
GET /api/v3/roles/1

# Explicit override — only sideload users
GET /api/v3/roles/1?include=users

# Suppress all sideloading
GET /api/v3/roles/1?include=
```

Sideloaded resources appear in a top-level `included` array per the JSON:API spec.

### Create / update request body

```http
POST /api/v3/articles
Content-Type: application/vnd.api+json
Authorization: Bearer <jwt>

{
  "data": {
    "type": "articles",
    "attributes": {
      "title": "My Article",
      "body": "Content here"
    }
  }
}
```

### JSON:API response example

```json
{
  "data": {
    "id": "1",
    "type": "articles",
    "attributes": {
      "title": "My Article",
      "body": "Content here",
      "published_at": "2026-06-08T10:00:00.000Z"
    }
  }
}
```

Attributes are driven by the model's `json_attrs` (minus `:id`, which is always the resource identifier). `methods:` entries become virtual attributes; `include:` entries produce relationship linkage and default sideloads.

---

## Custom Actions (v2 and v3)

Custom actions are dispatched by `Api::CustomActionDispatcher` in both v2 and v3. Responses are plain JSON (not JSON:API envelopes) in both versions. The bearer token must be sent via the `Authorization` header — embedding tokens in the action name is no longer supported.

### Pattern 1 — class method on the model

```ruby
class MyModel < ApplicationRecord
  # Called via: GET /api/v2/my_models?do=report
  #             GET /api/v3/my_models?do=report
  def self.custom_action_report(params)
    [{ total: count, params: params }, 200]
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

Routes for pattern 2 (same shape in v2 and v3):

```
GET    /api/v2/my_models/custom_action/report
GET    /api/v3/my_models/custom_action/report
GET    /api/v2/my_models/custom_action/report/:id
GET    /api/v3/my_models/custom_action/report/:id
POST / PUT / PATCH / DELETE also available in both versions
```

---

## JSON Serialisation DSL (`json_attrs`)

Each model can declare `self.json_attrs` to control the API response shape. In v2 this mirrors the Rails `as_json` API; in v3 the `[:only]` list drives the generated JSON:API serializer.

```ruby
class MyModel < ApplicationRecord
  cattr_accessor :json_attrs
  self.json_attrs = {
    only: [:id, :name, :status],      # attribute whitelist
    except: [:internal_notes],         # attribute blacklist (used when only: is absent)
    methods: [:computed_value],        # virtual attributes (callable on instance)
    include: {
      category: { only: [:id, :name] },
      tags:     { only: [:id, :label] }
    }
  }
end
```

**v2 behaviour**: `only`/`except`/`methods`/`include` are passed through Rails `as_json` on every response. Clients may override per-request via the `a` or `json_attrs` query/body parameter.

**v3 behaviour**:
- `only:` / `except:` — drive the generated JSON:API serializer's attribute list.
- `methods:` — each entry becomes a virtual attribute using `object.send(method)` (private methods are supported, consistent with Rails `as_json`).
- `include:` — each entry declares a relationship on the serializer and becomes a **default sideload**. The client can suppress or replace defaults with `?include=` (empty to suppress, comma-separated list to override).

When composing `json_attrs` across multiple concerns, use `ModelDrivenApi.smart_merge` to deep-merge without losing fields set by other concerns:

```ruby
self.json_attrs = ModelDrivenApi.smart_merge((json_attrs || {}), { only: [:id, :name] })
```

### Default `json_attrs` — no `Api::ModelName` concern required

A model doesn't need an explicit `Api::ModelName` concern just to get a working API shape.
`ModelDrivenApiDefaultJsonAttrs` is registered into
[`ThecoreBackendCommons::DefaultModuleRegistry`](../thecore_backend_commons/README.md#defaultmoduleregistry--shared-applicationrecordinherited-hook)
and automatically `include`d into every `ApplicationRecord` subclass as it's defined, setting
`self.json_attrs = { except: [] }` (every column, no `methods`, no sideloaded `include`) — the
simplest safe default. A model with its own `Api::ModelName` concern (or `ModelDrivenApiUser`/
`ModelDrivenApiRole`) is unaffected: that concern's `include` always runs after the default and
freely overrides or merges on top of it via `ModelDrivenApi.smart_merge`. Only a model with no
concern at all keeps the bare default.

**Temporary dependency note**: this currently requires `thecore_backend_commons` from a Gemfile
`git:` pin to its `release/3` branch, since the RubyGems release hasn't caught up with the
registry yet — see this repo's `CLAUDE.md` for the exact commit/removal condition.

---

## Raw SQL endpoint

Executes read-only SELECT queries. Authentication required. Only `SELECT` (and `WITH … SELECT`) statements are allowed; DDL and DML are rejected with HTTP 400.

### v2 — requires `result` key

```http
POST /api/v2/raw/sql
Authorization: Bearer <jwt>
Content-Type: application/json

{
  "query": "SELECT json_agg(u) AS result FROM users u WHERE u.admin = true"
}
```

The query **must** return a `result` column (use `json_agg` or `jsonb_agg`).

### v3 — plain JSON array

```http
GET /api/v3/raw/sql?query=SELECT+id,title+FROM+articles+LIMIT+10
Authorization: Bearer <jwt>

POST /api/v3/raw/sql
Authorization: Bearer <jwt>
Content-Type: application/json

{ "query": "SELECT id, title FROM articles ORDER BY created_at DESC LIMIT 10" }
```

Returns rows directly as a JSON array — no `result` key, no JSON:API envelope. This is a deliberate exception to JSON:API compliance for the SQL escape hatch.

---

## Info endpoints (v2 and v3)

All info endpoints are available under both `/api/v2/info/` and `/api/v3/info/`. v3 clients can use a single base URL for auth, CRUD, and info.

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

The v2 and v3 swagger specs are different — v2 documents plain JSON CRUD + Ransack + search + bulk ops; v3 documents JSON:API envelopes + filter/sort/page params + 204 on delete.

---

## ActiveStorage file uploads (v2)

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

---

## Web Push (VAPID) from a React client

This section is the complete integration guide for React apps that want to receive browser push notifications from a Thecore backend. The server-side setup (models, service, ActionCable channel) is documented in the [`thecore_backend_commons` README](../thecore_backend_commons/README.md#web-push-notifications-vapid).

### Prerequisites

1. Run `rails db:seed` on the backend — this generates the VAPID key pair automatically.
2. Set `vapid.contact_email` in RailsAdmin → Settings (e.g. `admin@yourapp.com`).
3. Your site must be served over **HTTPS** (required by the Push API in all browsers). `localhost` is exempt for development.

### Endpoint reference

All endpoints live under `/api/v2/push_subscribers/custom_action/`.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `vapid_public_key` | **No** | Returns the VAPID public key for `PushManager.subscribe` |
| `POST` | `subscribe` | Yes (JWT) | Registers or updates a push subscription for the current user |
| `POST` | `send_push` | Yes (JWT) | Creates a `PushMessage` and dispatches it to an active subscriber |
| `POST` | `acknowledge` | Yes (JWT) | Marks a message as `received` and/or `read` |

### Step 1 — Register a service worker

Create `public/sw.js` in your React app:

```javascript
// public/sw.js

self.addEventListener('push', event => {
  const data = event.data?.json() ?? {};
  event.waitUntil(
    self.registration.showNotification(data.title ?? 'Notification', {
      body: data.body,
      icon: data.icon ?? '/favicon.ico',
      data: { url: data.url },
    })
  );
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const url = event.notification.data?.url;
  if (url) {
    event.waitUntil(clients.openWindow(url));
  }
});
```

### Step 2 — Subscribe to push notifications

```javascript
// src/usePushSubscription.js
const API_BASE = process.env.REACT_APP_API_URL ?? '/api/v2';

// Convert a base64url string to a Uint8Array (required by PushManager)
function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(base64);
  return Uint8Array.from([...raw].map(c => c.charCodeAt(0)));
}

// Convert a PushSubscription key to a base64url string (required by the backend)
function keyToBase64(subscription, key) {
  return btoa(String.fromCharCode(...new Uint8Array(subscription.getKey(key))));
}

export async function subscribeToPush(jwtToken) {
  // 1. Register service worker
  const registration = await navigator.serviceWorker.register('/sw.js');

  // 2. Fetch the VAPID public key (no auth needed)
  const res = await fetch(`${API_BASE}/push_subscribers/custom_action/vapid_public_key`);
  const { vapid_public_key } = await res.json();

  // 3. Subscribe via the Push API
  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(vapid_public_key),
  });

  // 4. Register the subscription with the backend
  const registerRes = await fetch(
    `${API_BASE}/push_subscribers/custom_action/subscribe`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${jwtToken}`,
      },
      body: JSON.stringify({
        endpoint: subscription.endpoint,
        p256dh: keyToBase64(subscription, 'p256dh'),
        auth:   keyToBase64(subscription, 'auth'),
        user_agent: navigator.userAgent,
      }),
    }
  );

  const subscriber = await registerRes.json();
  // subscriber.id is the push_subscriber_id to use with ActionCable and send_push
  return subscriber;
}
```

Call this after the user logs in (a JWT is required for `subscribe`):

```javascript
import { subscribeToPush } from './usePushSubscription';

const subscriber = await subscribeToPush(jwtToken);
localStorage.setItem('push_subscriber_id', subscriber.id);
```

### Step 3 — Listen via ActionCable

Install the ActionCable client if you haven't already:

```bash
npm install @rails/actioncable
# or
yarn add @rails/actioncable
```

```javascript
// src/usePushChannel.js
import { createConsumer } from '@rails/actioncable';

const WS_URL = process.env.REACT_APP_WS_URL ?? 'ws://localhost:3000/cable';

export function connectPushChannel(jwtToken, subscriberId, onMessage) {
  // The JWT token is passed as a query parameter so the ActionCable
  // connection.rb can authenticate the WebSocket handshake.
  const consumer = createConsumer(`${WS_URL}?token=${jwtToken}`);

  const subscription = consumer.subscriptions.create(
    { channel: 'PushNotificationChannel', subscriber_id: subscriberId },
    {
      received(data) {
        // data is a PushMessage serialised as JSON:
        // { id, title, body, url, icon, sent_at, received_at, read_at }
        onMessage(data);
      },
      connected() {
        console.log('[PushNotificationChannel] connected');
      },
      disconnected() {
        console.log('[PushNotificationChannel] disconnected');
      },
    }
  );

  // Return a cleanup function
  return () => {
    subscription.unsubscribe();
    consumer.disconnect();
  };
}
```

Use it in a React component or hook:

```javascript
import { useEffect } from 'react';
import { connectPushChannel } from './usePushChannel';

function App() {
  const jwtToken = localStorage.getItem('token');
  const subscriberId = localStorage.getItem('push_subscriber_id');

  useEffect(() => {
    if (!jwtToken || !subscriberId) return;

    const disconnect = connectPushChannel(jwtToken, subscriberId, message => {
      console.log('New push message via ActionCable:', message);
      // Optionally acknowledge receipt immediately
      acknowledgeMessage(jwtToken, message.id, { received: true });
    });

    return disconnect; // cleanup on unmount
  }, [jwtToken, subscriberId]);
}
```

> **Tip:** use `user_id` instead of `subscriber_id` if you want to receive messages across all active subscriptions for the current user (e.g. multiple tabs):
> ```javascript
> { channel: 'PushNotificationChannel', user_id: currentUserId }
> ```

### Step 4 — Acknowledge receipt and read

```javascript
// src/pushApi.js
const API_BASE = process.env.REACT_APP_API_URL ?? '/api/v2';

export async function acknowledgeMessage(jwtToken, messageId, { received = false, read = false } = {}) {
  const res = await fetch(
    `${API_BASE}/push_subscribers/custom_action/acknowledge`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${jwtToken}`,
      },
      body: JSON.stringify({
        push_message_id: messageId,
        received,
        read,
      }),
    }
  );
  return res.json();
  // Response: { id, title, body, url, icon, sent_at, received_at, read_at, ... }
}
```

Call `received: true` as soon as the message arrives via ActionCable. Call `read: true` when the user opens or dismisses it. Fields are set only once — a second call with the same flag is a no-op (idempotent).

### Step 5 — Send a push from the backend (optional)

Normally the backend triggers pushes from jobs or model callbacks. If you need to trigger a push from a privileged frontend (e.g. an admin panel), use `send_push`:

```javascript
export async function sendPush(jwtToken, { subscriberId, title, body, url, icon }) {
  const res = await fetch(
    `${API_BASE}/push_subscribers/custom_action/send_push`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${jwtToken}`,
      },
      body: JSON.stringify({
        push_subscriber_id: subscriberId,
        title,
        body,
        url,   // optional
        icon,  // optional
      }),
    }
  );
  if (!res.ok) {
    const err = await res.json();
    throw new Error(err.error ?? `HTTP ${res.status}`);
  }
  return res.json(); // PushMessage record
}
```

### Full flow summary

```
React app                         Thecore backend
    │                                   │
    │── GET vapid_public_key ──────────►│  (no auth)
    │◄── { vapid_public_key: "..." } ───│
    │                                   │
    │  navigator.serviceWorker.register('/sw.js')
    │  registration.pushManager.subscribe({ applicationServerKey })
    │                                   │
    │── POST subscribe ────────────────►│  creates/updates PushSubscriber
    │◄── { id: 42, endpoint, ... } ─────│
    │                                   │
    │  createConsumer(wsUrl?token=jwt)  │
    │── WS upgrade ────────────────────►│  PushNotificationChannel#subscribed
    │◄── stream: push_notifications_subscriber_42
    │                                   │
    │  [backend dispatches push]        │
    │◄── Web Push payload (sw.js) ──────│  Webpush.payload_send via VAPID
    │  showNotification(title, body)    │
    │                                   │
    │◄── ActionCable data ──────────────│  PushNotificationChannel.broadcast_to
    │  onMessage(data)                  │
    │                                   │
    │── POST acknowledge (received) ───►│  message.received_at = now
    │── POST acknowledge (read) ────────►│  message.read_at = now
```

### Handling subscription expiry

Push service endpoints expire (the push provider returns HTTP 410). The backend automatically calls `subscriber.expire!` when this happens, but the client needs to re-subscribe on the next boot:

```javascript
export async function ensureSubscription(jwtToken) {
  // Re-subscribe unconditionally — subscribe_for upserts on endpoint,
  // so re-registering the same browser is always safe and clears expired_at.
  const sub = await subscribeToPush(jwtToken);
  localStorage.setItem('push_subscriber_id', sub.id);
  return sub;
}
```

### Permissions check

Before calling `subscribeToPush`, check that the browser supports push and the user has granted permission:

```javascript
export async function requestPushPermission() {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    console.warn('Web Push not supported in this browser');
    return false;
  }
  const permission = await Notification.requestPermission();
  return permission === 'granted';
}
```

---

## License

MIT
