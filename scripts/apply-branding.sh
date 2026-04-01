#!/bin/sh
# Apply Dataverse installation branding via Admin API (idempotent PUTs).
#
# Run after bootstrap.
#
# Auth:
#   - DATAVERSE_API_TOKEN env, or
#   - first line of /secrets/api/key
#
# Config:
#   - sources branding.env from BRANDING_ENV_PATH
#   - default: /branding/branding.env
#
# Conventions:
#   - empty value = skip that setting
#   - filesystem customization files should use /dv/docroot/branding/...
#   - navbar logo should use a web path like /logos/navbar/logo.svg

set -eu

BASE_URL="${DATAVERSE_INTERNAL_URL:-http://dataverse:8080}"
API="${BASE_URL%/}/api"
BRANDING_ENV="${BRANDING_ENV_PATH:-/branding/branding.env}"
STRICT="${APPLY_BRANDING_STRICT:-}"

log() {
  printf '%s\n' "apply-branding: $*" >&2
}

warn() {
  printf '%s\n' "apply-branding: WARNING $*" >&2
}

get_token() {
  if [ -n "${DATAVERSE_API_TOKEN:-}" ]; then
    printf '%s' "$DATAVERSE_API_TOKEN"
    return 0
  fi

  if [ -r /secrets/api/key ]; then
    # Use first line only, trimmed
    sed -n '1s/[[:space:]]*$//;1p' /secrets/api/key
    return 0
  fi

  return 1
}

if TOKEN="$(get_token)"; then
  :
else
  log "skipping (no DATAVERSE_API_TOKEN and no readable /secrets/api/key)"
  log "create a superuser token in the UI and save it on one line in secrets/api/key"
  if [ "$STRICT" = "1" ]; then
    exit 1
  fi
  exit 0
fi

if [ -f "$BRANDING_ENV" ]; then
  log "loading config from $BRANDING_ENV"
  # shellcheck disable=SC1090
  . "$BRANDING_ENV"
else
  log "no branding env found at $BRANDING_ENV, continuing with environment only"
fi

# Dataverse concatenates #{footerCopyrightAndYear}#{:FooterCopyright}
# with no separator in dataverse_footer.xhtml.
normalize_footer_copyright() {
  _val="$1"
  if [ -z "$_val" ]; then
    printf '%s' "$_val"
    return 0
  fi

  case "$_val" in
    " "*) ;;
    "	"*) ;;
    "-"*|"|"*|"("*) ;;
    "—"*) ;;
    *) _val=" ${_val}" ;;
  esac

  printf '%s' "$_val"
}

FOOTER_COPYRIGHT="$(normalize_footer_copyright "${FOOTER_COPYRIGHT:-}")"

normalize_bool() {
  _val="$1"
  case "$_val" in
    true|TRUE|1|yes|YES|on|ON) printf '%s' "true" ;;
    false|FALSE|0|no|NO|off|OFF) printf '%s' "false" ;;
    *) printf '%s' "$_val" ;;
  esac
}

curl_put_setting() {
  _name="$1"
  _val="$2"

  if [ -z "$_val" ]; then
    log "skip ${_name} (empty)"
    return 0
  fi

  log "PUT ${_name}"
  _code="$(
    curl -sS -o /dev/null -w "%{http_code}" \
      -X PUT \
      -H "X-Dataverse-key: ${TOKEN}" \
      --data-binary "$_val" \
      "${API}/admin/settings/${_name}"
  )"

  case "$_code" in
    200|204)
      log "${_name} -> HTTP ${_code}"
      ;;
    *)
      warn "${_name} -> HTTP ${_code} (check token, setting name, and Dataverse logs)"
      ;;
  esac
}

apply_setting_from_env() {
  _setting_name="$1"
  _env_value="$2"
  curl_put_setting "$_setting_name" "$_env_value"
}

probe_logo_url() {
  _logo_url="$1"

  if [ -z "$_logo_url" ]; then
    return 0
  fi

  _probe="${BASE_URL%/}${_logo_url}"
  _code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 "$_probe" || true)"
  log "GET ${_logo_url} (expect 200) -> HTTP ${_code}"

  if [ "$_code" != "200" ]; then
    warn "navbar logo URL did not resolve"
    warn "check LOGO_CUSTOMIZATION_FILE and the bind mount for branding/docroot/logos -> /dv/docroot/logos"
    warn "if the navbar image is broken, View Source may show multiple img tags for navbar vs root theme branding"
  fi
}

# ------------------------------------------------------------------------------
# Core branding settings
# ------------------------------------------------------------------------------

apply_setting_from_env ":InstallationName" "${INSTALLATION_NAME:-}"
apply_setting_from_env ":LogoCustomizationFile" "${LOGO_CUSTOMIZATION_FILE:-}"
apply_setting_from_env ":HeaderCustomizationFile" "${HEADER_CUSTOMIZATION_FILE:-}"
apply_setting_from_env ":HomePageCustomizationFile" "${HOME_PAGE_CUSTOMIZATION_FILE:-}"
apply_setting_from_env ":FooterCustomizationFile" "${FOOTER_CUSTOMIZATION_FILE:-}"
apply_setting_from_env ":StyleCustomizationFile" "${STYLE_CUSTOMIZATION_FILE:-}"
apply_setting_from_env ":FooterCopyright" "${FOOTER_COPYRIGHT:-}"
apply_setting_from_env ":NavbarAboutUrl" "${NAVBAR_ABOUT_URL:-}"
apply_setting_from_env ":NavbarSupportUrl" "${NAVBAR_SUPPORT_URL:-}"
apply_setting_from_env ":NavbarGuidesUrl" "${NAVBAR_GUIDES_URL:-}"

if [ -n "${DISABLE_ROOT_DATAVERSE_THEME:-}" ]; then
  DISABLE_ROOT_DATAVERSE_THEME="$(normalize_bool "$DISABLE_ROOT_DATAVERSE_THEME")"
  apply_setting_from_env ":DisableRootDataverseTheme" "$DISABLE_ROOT_DATAVERSE_THEME"
else
  log "skip :DisableRootDataverseTheme (empty)"
fi

probe_logo_url "${LOGO_CUSTOMIZATION_FILE:-}"

log "done"