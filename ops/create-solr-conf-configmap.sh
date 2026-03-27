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
  echo "  Use ./ops/fetch-dataverse-solr-conf.sh (IQSS + Solr _default resources) — see ops/solr-init-setup.md" >&2
  exit 1
fi
if [[ ! -f "${CONF_DIR}/stopwords.txt" ]]; then
  echo "error: missing stopwords.txt — schema.xml references it; run ./ops/merge-solr811-default-resources.sh \"${CONF_DIR}\"" >&2
  exit 1
fi
if [[ ! -f "${CONF_DIR}/lang/stopwords_en.txt" ]]; then
  echo "error: missing lang/stopwords_en.txt — run ./ops/fetch-dataverse-solr-conf.sh (merge step)" >&2
  exit 1
fi

# kubectl create configmap --from-file=DIR only adds *top-level* files; it skips subdirs, so lang/
# never reaches the cluster. Pack the full tree as one .tgz; load-solr-init untars it (see chart).
TMP_TAR="$(mktemp)"
TMP_YAML="$(mktemp)"
cleanup() { rm -f "${TMP_TAR}" "${TMP_YAML}"; }
trap cleanup EXIT
COPYFILE_DISABLE=1 tar czf "${TMP_TAR}" -C "${CONF_DIR}" .

kubectl create configmap "$NAME" \
  --namespace="$NAMESPACE" \
  --from-file=solr-conf.tgz="${TMP_TAR}" \
  --dry-run=client -o yaml >"${TMP_YAML}"

# Replace (not merge-apply) so an old flat ConfigMap’s `data:` keys are dropped; otherwise the pod
# still mounts dozens of stale files and it is unclear that only solr-conf.tgz matters.
if kubectl get configmap "$NAME" --namespace="$NAMESPACE" >/dev/null 2>&1; then
  kubectl replace -f "${TMP_YAML}"
else
  kubectl apply -f "${TMP_YAML}"
fi

echo "ConfigMap $NAME applied in namespace $NAMESPACE (binary key solr-conf.tgz — full tree including lang/)"
echo "Verify: kubectl get configmap \"$NAME\" -n \"$NAMESPACE\" -o json | grep -E 'binaryData|solr-conf'"
