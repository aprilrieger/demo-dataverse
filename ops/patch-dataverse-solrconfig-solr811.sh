#!/usr/bin/env bash
# IQSS Dataverse v6.10+ ships conf/solr/solrconfig.xml aligned with Solr 9 (luceneMatchVersion 9.x and
# solr.NumFieldLimitingUpdateRequestProcessorFactory). That class does not exist on Solr 8.11.x — core
# creation fails with: Caused by: solr.NumFieldLimitingUpdateRequestProcessorFactory
#
# This removes the Solr-9-only URP, drops it from the schemaless chain, and sets luceneMatchVersion to
# 8.11.2 for clusters running Bitnami Solr 8.11.x (see ops/solr-init-setup.md).
#
# Usage:
#   ./ops/patch-dataverse-solrconfig-solr811.sh /path/to/solrconfig.xml

set -euo pipefail

F="${1:?usage: $0 /path/to/solrconfig.xml}"
[[ -f "$F" ]] || { echo "error: not a file: $F" >&2; exit 1; }

tmp="$(mktemp)"
perl -0777 -pe '
  s/\n  <updateProcessor class="solr\.NumFieldLimitingUpdateRequestProcessorFactory" name="max-fields">\n    <int name="maxFields">\d+<\/int>\n    <bool name="warnOnly">\w+<\/bool>\n  <\/updateProcessor>//s;
  s/processor="uuid,remove-blank,field-name-mutating,max-fields,/processor="uuid,remove-blank,field-name-mutating,/;
  s/<luceneMatchVersion>9\.\d+<\/luceneMatchVersion>/<luceneMatchVersion>8.11.2<\/luceneMatchVersion>/;
' "$F" > "$tmp"
mv "$tmp" "$F"
echo "Patched $F for Solr 8.11.x (removed NumFieldLimiting URP, luceneMatchVersion 8.11.2)."
