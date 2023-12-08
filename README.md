# Vana OAuth
Vana's OAuth services, using [Ory Hydra](https://github.com/ory/hydra).

Ory Hydra provides [two services](https://www.ory.sh/docs/hydra/self-hosted/production#exposing-administrative-and-public-api-endpoints) to allow Vana to act as an OAuth server.

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

These services could be deployed to a single long-running server that exposes two ports, however, we deploy two separate Google Cloud Run services to keep our architecture serverless.

## Deployment
Both Ory services (public and admin) are hosted on Google Cloud Run. The following deployments scripts can be run:
```sh
# Deploy public endpoint
./scripts/deploy-hydra.sh public development

# Deploy admin endpoint
./scripts/deploy-hydra.sh admin development
```

## Authenticating with admin endpoint
```sh
# Activate vana-app-user service account
gcloud auth activate-service-account --key-file=".../vana-app-user-development.json"

# Print identity token for vana-app-user
gcloud auth print-identity-token --impersonate-service-account=vana-app-user@corsali-development.iam.gserviceaccount.com --audiences="https://ory-hydra-admin-development-khacypbkia-uc.a.run.app"
> eyJhb...Ts1KQ
```
This token can then be used in the `Authorization: Bearer <token>` header to any API calls to the admin endpoint.
