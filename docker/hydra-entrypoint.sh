#!/usr/bin/env sh
set -eu

required_vars="
DATABASE_URL
LOGIN_URL
DEVICE_URL
ORY_PUBLIC_URL
ORY_ADMIN_URL
COOKIE_DOMAIN
SYSTEM_SECRET
COOKIE_SECRET
PAGINATION_SECRET
OIDC_PAIRWISE_SALT
"

for var in $required_vars; do
  eval "value=\${$var:-}"
  if [ -z "$value" ]; then
    echo "$var is not set" >&2
    exit 1
  fi
done

: "${CORS_DEBUG:=false}"
: "${LOG_LEAK_SENSITIVE_VALUES:=false}"
: "${OAUTH2_EXPOSE_INTERNAL_ERRORS:=false}"

cat > /tmp/hydra.yml <<EOF
serve:

  admin:
    port: 8080
    cors:
      enabled: true
      allowed_origins:
        - "$LOGIN_URL"
      allowed_methods:
        - POST
        - GET
        - PUT
        - PATCH
        - DELETE
        - OPTIONS
      allowed_headers:
        - Access-Control-Allow-Origin
        - X-Requested-With
        - Authorization
        - Content-Type
        - Origin
        - Cookie
      exposed_headers:
        - Origin
        - Content-Type
        - Access-Control-Allow-Origin
        - Set-Cookie
      allow_credentials: true
      debug: $CORS_DEBUG

  public:
    port: 8080
    cors:
      enabled: true
      allowed_origins:
        - "$LOGIN_URL"
      allowed_methods:
        - POST
        - GET
        - PUT
        - PATCH
        - DELETE
        - OPTIONS
      allowed_headers:
        - Access-Control-Allow-Origin
        - X-Requested-With
        - Authorization
        - Content-Type
        - Origin
        - Cookie
      exposed_headers:
        - Origin
        - Content-Type
        - Access-Control-Allow-Origin
        - Set-Cookie
      allow_credentials: true
      debug: $CORS_DEBUG

  cookies:
    same_site_mode: None
    same_site_legacy_workaround: true
    domain: "$COOKIE_DOMAIN"
    secure: true
    paths:
      session: "/"

log:
  leak_sensitive_values: $LOG_LEAK_SENSITIVE_VALUES

urls:
  self:
    public: "$ORY_PUBLIC_URL"
    admin: "$ORY_ADMIN_URL"
    issuer: "$ORY_PUBLIC_URL"
  consent: "$LOGIN_URL/consent"
  login: "$LOGIN_URL/login"
  logout: "$LOGIN_URL/logout"
  error: "$LOGIN_URL/error"
  device:
    verification: "$DEVICE_URL/device"
    success: "$DEVICE_URL/device-success"

dsn: "$DATABASE_URL"

secrets:
  system:
    - "$SYSTEM_SECRET"
  cookie:
    - "$COOKIE_SECRET"
  pagination:
    - "$PAGINATION_SECRET"

oidc:
  subject_identifiers:
    supported_types:
      - pairwise
      - public
    pairwise:
      salt: "$OIDC_PAIRWISE_SALT"

oauth2:
  expose_internal_errors: $OAUTH2_EXPOSE_INTERNAL_ERRORS

ttl:
  access_token: 168h
  id_token: 168h
EOF

case "${1:-}" in
  serve|migrate)
    exec hydra "$@" -c /tmp/hydra.yml
    ;;
  *)
    exec hydra "$@"
    ;;
esac
