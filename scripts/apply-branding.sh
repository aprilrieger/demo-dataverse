#!/bin/sh
# Apply Dataverse installation branding via Admin API (idempotent PUTs).
# Run after bootstrap. Token: DATAVERSE_API_TOKEN env or first line of /secrets/api/key.
# Configuration: source branding/branding.env (repo-relative path when run from compose).

set -eu

BASE_URL="${DATAVERSE_INTERNAL_URL:-http://dataverse:8080}"
API="${BASE_URL%/}/api"

if [ -n "${DATAVERSE_API_TOKEN:-}" ]; then
  TOKEN="$DATAVERSE_API_TOKEN"
elif [ -r /secrets/api/key ]; then
  TOKEN=$(tr -d '[:space:]' </secrets/api/key)
else
  TOKEN=""
fi

if [ -z "$TOKEN" ]; then
  echo "apply-branding: skipping (no DATAVERSE_API_TOKEN and no readable /secrets/api/key)" >&2
  echo "apply-branding: create a superuser token in the UI and save it on one line in secrets/api/key" >&2
  if [ "${APPLY_BRANDING_STRICT:-}" = "1" ]; then
    exit 1
  fi
  exit 0
fi

BRANDING_ENV="${BRANDING_ENV_PATH:-/branding/branding.env}"
if [ -f "$BRANDING_ENV" ]; then
  # shellcheck disable=SC1090
  . "$BRANDING_ENV"
fi

# Dataverse concatenates #{footerCopyrightAndYear}#{:FooterCopyright} with no space (dataverse_footer.xhtml).
if [ -n "${FOOTER_COPYRIGHT:-}" ]; then
  case "$FOOTER_COPYRIGHT" in
    " "*) ;;
    "	"*) ;;
    "-"*|"|"*|"("*) ;;
    "—"*) ;;
    *) FOOTER_COPYRIGHT=" ${FOOTER_COPYRIGHT}" ;;
  esac
fi

curl_put_setting() {
  _name="$1"
  _val="$2"
  if [ -z "$_val" ]; then
    return 0
  fi
  printf '%s' "apply-branding: PUT ${_name}\n" >&2
  _code=$(curl -sS -o /dev/null -w "%{http_code}" -X PUT \
    -H "X-Dataverse-key: ${TOKEN}" \
    --data-binary "$_val" \
    "${API}/admin/settings/${_name}")
  if [ "$_code" != "200" ] && [ "$_code" != "204" ]; then
    echo "apply-branding: WARNING ${_name} -> HTTP ${_code} (check superuser token)" >&2
  fi
}

# --- Optional paths: docroot-relative URLs (see Installation Guide — Branding)
curl_put_setting ":InstallationName" "${INSTALLATION_NAME:-}"
curl_put_setting ":LogoCustomizationFile" "${LOGO_CUSTOMIZATION_FILE:-}"
curl_put_setting ":HeaderCustomizationFile" "${HEADER_CUSTOMIZATION_FILE:-}"
curl_put_setting ":HomePageCustomizationFile" "${HOME_PAGE_CUSTOMIZATION_FILE:-}"
curl_put_setting ":FooterCustomizationFile" "${FOOTER_CUSTOMIZATION_FILE:-}"
curl_put_setting ":StyleCustomizationFile" "${STYLE_CUSTOMIZATION_FILE:-}"
curl_put_setting ":FooterCopyright" "${FOOTER_COPYRIGHT:-}"
curl_put_setting ":NavbarAboutUrl" "${NAVBAR_ABOUT_URL:-}"
curl_put_setting ":NavbarSupportUrl" "${NAVBAR_SUPPORT_URL:-}"
curl_put_setting ":NavbarGuidesUrl" "${NAVBAR_GUIDES_URL:-}"

if [ -n "${DISABLE_ROOT_DATAVERSE_THEME:-}" ]; then
  curl_put_setting ":DisableRootDataverseTheme" "$DISABLE_ROOT_DATAVERSE_THEME"
fi

if [ -n "${LOGO_CUSTOMIZATION_FILE:-}" ]; then
  _probe="${BASE_URL}${LOGO_CUSTOMIZATION_FILE}"
  _code=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 "$_probe" || true)
  echo "apply-branding: GET ${LOGO_CUSTOMIZATION_FILE} (expect 200) -> HTTP ${_code}" >&2
  if [ "$_code" != "200" ]; then
    echo "apply-branding: if the navbar image is broken, fix this URL or the bind mount; View Source may show two <img> tags (navbar vs root theme)." >&2
  fi
fi

echo "apply-branding: done" >&2
