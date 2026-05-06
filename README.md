# Vana OAuth

Vana's development and production OAuth services, using [Ory Hydra](https://github.com/ory/hydra) `v26.2.0`.

Login Playground: https://vana-com.github.io/vana-oauth/

Ory Hydra exposes [two services](https://www.ory.sh/docs/hydra/self-hosted/production#exposing-administrative-and-public-api-endpoints) and this repo keeps that public/admin split intact.

Public endpoints: deployed to `https://oauth-dev.vana.org` and `https://oauth.vana.org`

```
/.well-known/jwks.json
/.well-known/openid-configuration
/oauth2/auth
/oauth2/device/auth
/oauth2/device/verify
/oauth2/token
/oauth2/revoke
/oauth2/fallbacks/consent
/oauth2/fallbacks/error
/oauth2/sessions/logout
/userinfo
```

Admin endpoints: deployed to `https://oauth-admin-dev.vana.org` and `https://oauth-admin.vana.org`

The admin endpoint stays private; only the public endpoint is exposed for browser-facing traffic.

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

Both Hydra services are hosted on Google Cloud Run. The deploy script renders `hydra.template.yml` from Doppler secrets, builds the matching container, and deploys one service at a time. Secrets are loaded at deploy/runtime from Doppler; they are not baked into the image:

```sh
# Deploy public endpoint
./scripts/deploy-hydra.sh public development

# Deploy admin endpoint
./scripts/deploy-hydra.sh admin development
```

The script accepts `development` or `production`, and it should be run from the repo root.

When bumping Hydra versions, run the one-shot migration helper first from an environment that can reach the target database:

```sh
./scripts/migrate-hydra.sh development
```

The helper uses the same Doppler-backed config render as deployment, but it only runs `hydra migrate sql` and does not deploy any service.

Run the migration helper before deploying a Hydra version change.

Required Doppler values:

- `DATABASE_URL`
- `LOGIN_URL`
- `DEVICE_URL`
- `ORY_PUBLIC_URL`
- `ORY_ADMIN_URL`
- `COOKIE_DOMAIN`
- `SYSTEM_SECRET`
- `COOKIE_SECRET`
- `PAGINATION_SECRET`
- `OIDC_PAIRWISE_SALT`

`LOGIN_URL` is the account app login/consent/logout base URL. `DEVICE_URL`
is the account app device-flow base URL; Hydra appends `/device` and
`/device-success` from `hydra.template.yml`. Do not include a trailing slash
on either value.

`hydra.template.yml` defines global fallback TTLs. Client records in Hydra may
override access-token and refresh-token lifetimes, so treat Hydra client config
as the source of truth for a specific client.

## Authenticating with admin endpoint

```sh
# Activate vana-app-user service account
gcloud auth activate-service-account --key-file=".../vana-app-user-development.json"

# Print identity token for vana-app-user
gcloud auth print-identity-token --impersonate-service-account=vana-app-user@corsali-development.iam.gserviceaccount.com --audiences="https://oauth-admin-dev.vana.org"
> eyJhb...Ts1KQ
```

This token can then be used in the `Authorization: Bearer <token>` header to any API calls to the admin endpoint.
