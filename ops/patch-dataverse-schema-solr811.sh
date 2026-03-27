#!/usr/bin/env bash
# IQSS Dataverse v6.10.1 conf/solr/schema.xml uses legacy <tokenizer name="..."/> and <filter name="..."/>
# shorthand (Solr "managed schema" style). Solr 8.11+ (e.g. Bitnami legacy 8.11.2) rejects these with:
#   analyzer/tokenizer: missing mandatory attribute 'class'
# This rewrites those few lines to explicit factory classes (same mapping as Solr examples).
#
# Usage:
#   ./ops/patch-dataverse-schema-solr811.sh /path/to/schema.xml

set -euo pipefail

F="${1:?usage: $0 /path/to/schema.xml}"
[[ -f "$F" ]] || { echo "error: not a file: $F" >&2; exit 1; }

tmp="$(mktemp)"
sed \
  -e 's|<tokenizer name="whitespace"/>|<tokenizer class="solr.WhitespaceTokenizerFactory"/>|g' \
  -e 's|<tokenizer name="standard"/>|<tokenizer class="solr.StandardTokenizerFactory"/>|g' \
  -e 's|<filter name="stop" |<filter class="solr.StopFilterFactory" |g' \
  -e 's|<filter name="lowercase"/>|<filter class="solr.LowerCaseFilterFactory"/>|g' \
  -e 's|<filter name="synonymGraph" |<filter class="solr.SynonymGraphFilterFactory" |g' \
  "$F" > "$tmp"
mv "$tmp" "$F"
echo "Patched $F for Solr 8.11+ (explicit tokenizer/filter classes)."
