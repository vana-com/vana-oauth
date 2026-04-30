# Vana OAuth
Vana's production-style OAuth services, using [Ory Hydra](https://github.com/ory/hydra) `v26.2.0`.

Login Playground: https://vana-com.github.io/vana-oauth/

Ory Hydra exposes [two services](https://www.ory.sh/docs/hydra/self-hosted/production#exposing-administrative-and-public-api-endpoints) and this repo keeps that public/admin split intact.

Public endpoints: deployed to `https://development-oauth.vana.com`
```
/.well-known/jwks.json
/.well-known/openid-configuration
/oauth2/auth
/oauth2/token
/oauth2/revoke
/oauth2/fallbacks/consent
/oauth2/fallbacks/error
/oauth2/sessions/logout
/userinfo
```

Admin endpoints: deployed to `https://development-oauth-admin.vana.com`
```
All /clients endpoints.
All /keys endpoints.
All /health, /admin/metrics/prometheus, /admin/version endpoints.
All /oauth2/auth/requests endpoints.
/oauth2/introspect.
/oauth2/flush.
```

These services could be deployed to a single long-running server that exposes two ports, however, Vana deploys two separate Google Cloud Run services so the public and admin surfaces stay isolated and serverless.

## Deployment
Both Hydra services are hosted on Google Cloud Run. The deploy script renders `hydra.template.yml` from Doppler secrets, builds the matching container, and deploys one service at a time:
```sh
# Deploy public endpoint
./scripts/deploy-hydra.sh public development

# Deploy admin endpoint
./scripts/deploy-hydra.sh admin development
```
The script accepts `development`, `staging`, or `production`, and it should be run from the repo root.

When bumping Hydra versions, run the one-shot migration helper first from an environment that can reach the target database:
```sh
./scripts/migrate-hydra.sh development
```
The helper uses the same Doppler-backed config render as deployment, but it only runs `hydra migrate sql` and does not deploy any service.

Required Doppler values:

- `DATABASE_URL`
- `LOGIN_URL`
- `ORY_PUBLIC_URL`
- `ORY_ADMIN_URL`
- `COOKIE_DOMAIN`
- `SYSTEM_SECRET`
- `COOKIE_SECRET`
- `PAGINATION_SECRET`
- `OIDC_PAIRWISE_SALT`

## Authenticating with admin endpoint
```sh
# Activate vana-app-user service account
gcloud auth activate-service-account --key-file=".../vana-app-user-development.json"

# Print identity token for vana-app-user
gcloud auth print-identity-token --impersonate-service-account=vana-app-user@corsali-development.iam.gserviceaccount.com --audiences="https://development-oauth-admin.vana.com"
> eyJhb...Ts1KQ
```
This token can then be used in the `Authorization: Bearer <token>` header to any API calls to the admin endpoint.
