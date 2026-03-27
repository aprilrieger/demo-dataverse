#!/usr/bin/env bash
# Create/update the ConfigMap used by Helm solrInit.confConfigMap (Dataverse Solr conf/ files).
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

kubectl create configmap "$NAME" \
  --namespace="$NAMESPACE" \
  --from-file="$CONF_DIR" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "ConfigMap $NAME applied in namespace $NAMESPACE"
