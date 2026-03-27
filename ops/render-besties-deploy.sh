#!/usr/bin/env bash
# Render ops/besties-deploy.tmpl.yaml → a concrete Helm values file (same as CI envsubst step).
#
# Usage:
#   export DB_PASSWORD='...'
#   ./ops/render-besties-deploy.sh
#   ./ops/render-besties-deploy.sh /path/to/out.yaml
#
# Optional Solr basic auth: SOLR_ADMIN_USER / SOLR_ADMIN_PASSWORD or SOLR_AUTH_PREFIX
# Optional: export DOLLAR='$' (script sets this if unset)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-${ROOT}/ops/besties-deploy.yaml}"

if [[ -z "${DB_PASSWORD:-}" ]]; then
  echo "error: export DB_PASSWORD='your-postgres-password'" >&2
  exit 1
fi
export DOLLAR="${DOLLAR:-\$}"

if ! command -v envsubst >/dev/null 2>&1; then
  echo "error: envsubst not found (e.g. brew install gettext)" >&2
  exit 1
fi

envsubst < "${ROOT}/ops/besties-deploy.tmpl.yaml" > "${OUT}"
echo "Wrote ${OUT}"
