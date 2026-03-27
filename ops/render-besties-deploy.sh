#!/usr/bin/env bash
# Render ops/besties-deploy.tmpl.yaml → a concrete Helm values file (same as CI envsubst step).
#
# Usage:
#   export DB_PASSWORD='...'
#   ./ops/render-besties-deploy.sh
#   ./ops/render-besties-deploy.sh /path/to/out.yaml
#
# Optional: export DOLLAR='$' (script sets this if unset)
# podAnnotations deploy.github.com/run-id: defaults to "local" so values are valid; bump GITHUB_RUN_ID to force a rollout locally.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-${ROOT}/ops/besties-deploy.yaml}"

if [[ -z "${DB_PASSWORD:-}" ]]; then
  echo "error: export DB_PASSWORD='your-postgres-password'" >&2
  exit 1
fi
export DOLLAR="${DOLLAR:-\$}"
export GITHUB_RUN_ID="${GITHUB_RUN_ID:-local}"
export SMTP_PORT="${SMTP_PORT:-25}"
export SOCKET_PORT="${SOCKET_PORT:-${SMTP_PORT}}"
export SMTP_PASSWORD="${SMTP_PASSWORD:-${MAIL_SMTP_PASSWORD:-}}"
if [[ -z "${NO_REPLY_EMAIL:-}" && -n "${SMTP_DOMAIN:-}" ]]; then
  export NO_REPLY_EMAIL="noreply@${SMTP_DOMAIN}"
fi

if ! command -v envsubst >/dev/null 2>&1; then
  echo "error: envsubst not found (e.g. brew install gettext)" >&2
  exit 1
fi

envsubst < "${ROOT}/ops/besties-deploy.tmpl.yaml" > "${OUT}"
echo "Wrote ${OUT}"
