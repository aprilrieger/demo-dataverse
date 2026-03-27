#!/usr/bin/env bash
# Create/update the ConfigMap used by Helm solrInit.confConfigMap (Dataverse Solr conf/ files).
# Prefer downloading official conf first: ./ops/fetch-dataverse-solr-conf.sh
#
# Usage:
#   ./ops/create-solr-conf-configmap.sh /path/to/solr/conf demo-dataverse-besties
#
# The directory must contain schema.xml, solrconfig.xml, etc. from the Dataverse release that
# matches your Dataverse image (see ops/solr-init-setup.md).

set -euo pipefail

CONF_DIR="${1:?usage: $0 /path/to/solr/conf NAMESPACE}"
NAMESPACE="${2:?usage: $0 /path/to/solr/conf NAMESPACE}"
NAME="${SOLR_CONF_CONFIGMAP_NAME:-dataverse-besties-solr-conf}"

CONF_DIR="$(cd "$CONF_DIR" && pwd)"
if [[ ! -f "${CONF_DIR}/solrconfig.xml" ]]; then
  echo "error: ${CONF_DIR} must contain solrconfig.xml (full Dataverse Solr conf), not schema.xml alone." >&2
  echo "  This repo's docker-compose bind-mounts only ./config/schema.xml onto the core conf path, so" >&2
  echo "  docker cp solr:/var/solr/data/dataverse/conf often copies just schema.xml." >&2
  echo "  Find the real conf in the Solr image, e.g.:" >&2
  echo "    docker compose exec solr find /opt/solr /var/solr -name solrconfig.xml 2>/dev/null" >&2
  echo "  Or use the Dataverse release / IQSS conf tree — see ops/solr-init-setup.md" >&2
  exit 1
fi

kubectl create configmap "$NAME" \
  --namespace="$NAMESPACE" \
  --from-file="$CONF_DIR" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "ConfigMap $NAME applied in namespace $NAMESPACE"
echo "Verify: kubectl describe configmap \"$NAME\" -n \"$NAMESPACE\" (Data keys); dotted names break jsonpath, e.g. {.data.solrconfig.xml}."
