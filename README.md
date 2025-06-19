This is part of Thecore framework: https://github.com/gabrieletassoni/thecore/tree/release/3

## Authorization

It's enabled to LDAP (Active Directory and othe LDAP Based local service) and to oauth2 (Google Workspace and Microsoft Entra ID) services.

### 📘 Register OAuth Apps

To use OAuth2 for authentication, you need to register your application with the OAuth provider (Google or Microsoft). Follow these steps, which are specific to each provider and aimed at a demo frontend application running on `http://localhost:5173`.
 
#### ✅ Google OAuth Client Setup
 
Go to: https://console.cloud.google.com/apis/credentials
Create OAuth 2.0 Client ID
Choose Web Application
Add to “Authorized JavaScript Origins”:
http://localhost:5173
Add to “Authorized redirect URIs” (used by Google, not backend):
http://localhost:5173 (for frontend access only)
Save your Client ID
 
 
#### ✅ Microsoft Entra ID OAuth Setup
 
Go to https://portal.azure.com
Microsoft Entra ID → App registrations → New registration
Set redirect URI to http://localhost:5173 (type: SPA)
Note the:
Application (client) ID
Directory (tenant) ID
Under Authentication tab:
Add platform: “Single-page application”
Add http://localhost:5173 to Redirect URIs

### Save your Client ID and Tenant ID
You will need these IDs to configure the backend.

### 📘 Configure OAuth in Thecore
To configure OAuth in Thecore backend, you need to set the following environment variables in your `.env` file or `environmet:` configuration in docker-compose.yml:

```plaintext
# OAuth Configuration
# Microsoft OAuth
ENTRA_CLIENT_ID: "your-client-id"
ENTRA_CLIENT_SECRET: "your-client-secret"
ENTRA_TENANT_ID: "your-tenant-id"

# Google OAuth
GOOGLE_CLIENT_ID: "your-client-id.apps.googleusercontent.com"
GOOGLE_CLIENT_SECRET: "your-client-secret"
```

In the Frontend applciation, you will need to set the following environment variables in your `.env` file:

```plaintext
# OAuth Configuration
# Google OAuth
VITE_GOOGLE_CLIENT_ID=your-client-id

# Microsoft OAuth
VITE_AZURE_CLIENT_ID=your-client-id
VITE_AZURE_TENANT_ID=your-tenant-id

# OAuth Callback URLs
VITE_API_URL=http://yourdomain/api/v2/auth/google_oauth2/callback
```
