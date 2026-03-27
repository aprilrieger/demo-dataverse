#!/usr/bin/env bash
# Download official IQSS Dataverse Solr conf/ from GitHub (Path A — matches Dataverse releases).
#
# For v6.10.x this is the full tree under https://github.com/IQSS/dataverse/tree/v6.10.1/conf/solr
# (schema.xml, solrconfig.xml, update-fields.sh). Align DATAVERSE_GIT_REF with your Payara image.
# After download (and optional OVERLAY_REPO_SCHEMA), runs ops/patch-dataverse-schema-solr811.sh so
# schema.xml works with Solr 8.11+ (Bitnami): IQSS v6.10.1 uses legacy <tokenizer name="..."/> lines.
#
# Usage:
#   ./ops/fetch-dataverse-solr-conf.sh
#   ./ops/fetch-dataverse-solr-conf.sh /path/to/out-dir
#   DATAVERSE_GIT_REF=v6.9.0 ./ops/fetch-dataverse-solr-conf.sh
#   OVERLAY_REPO_SCHEMA=1 ./ops/fetch-dataverse-solr-conf.sh   # after download, copy ./config/schema.xml
#
# Then:
#   ./ops/create-solr-conf-configmap.sh "$(pwd)/dv-solr-conf" demo-dataverse-besties

set -euo pipefail

OPS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${OPS}/.." && pwd)"
OUT="${1:-${ROOT}/dv-solr-conf}"
REF="${DATAVERSE_GIT_REF:-v6.10.1}"
BASE="https://raw.githubusercontent.com/IQSS/dataverse/${REF}/conf/solr"

mkdir -p "$OUT"
for f in schema.xml solrconfig.xml update-fields.sh; do
  echo "Fetching ${BASE}/${f}"
  curl -fsSL -o "${OUT}/${f}" "${BASE}/${f}"
done
chmod +x "${OUT}/update-fields.sh" 2>/dev/null || true

if [[ "${OVERLAY_REPO_SCHEMA:-}" == "1" ]]; then
  if [[ -f "${ROOT}/config/schema.xml" ]]; then
    echo "Overlaying ${ROOT}/config/schema.xml -> ${OUT}/schema.xml"
    cp "${ROOT}/config/schema.xml" "${OUT}/schema.xml"
  else
    echo "warning: OVERLAY_REPO_SCHEMA=1 but ${ROOT}/config/schema.xml missing" >&2
  fi
fi

chmod +x "${OPS}/patch-dataverse-schema-solr811.sh" 2>/dev/null || true
"${OPS}/patch-dataverse-schema-solr811.sh" "${OUT}/schema.xml"

echo "Wrote Dataverse ${REF} Solr conf to ${OUT}"
echo "Next: ./ops/create-solr-conf-configmap.sh \"${OUT}\" <namespace>"
