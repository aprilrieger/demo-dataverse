#!/usr/bin/env bash
# Copy Solr 8.11.x _default configset helpers (lang/, stopwords.txt, synonyms.txt, protwords.txt)
# from the official lucene-solr release tag into a conf directory.
#
# IQSS Dataverse only publishes schema.xml + solrconfig.xml (+ script) in Git; schema.xml references
# stopwords.txt and lang/*.txt from Solr's standard configset. Docker Compose "works" because the
# Solr image already ships those files on disk — Kubernetes solrInit uploads only what's in the
# ConfigMap, so we merge these files here.
#
# Usage:
#   ./ops/merge-solr811-default-resources.sh /path/to/dv-solr-conf
#
# Optional: LUCENE_SOLR_TAG=releases/lucene-solr/8.11.2 (must match Bitnami Solr minor if possible)

set -euo pipefail

OUT="${1:?usage: $0 /path/to/dv-solr-conf}"
OUT="$(cd "$OUT" && pwd)"

TAG="${LUCENE_SOLR_TAG:-releases/lucene-solr/8.11.2}"
ARCHIVE_URL="https://codeload.github.com/apache/lucene-solr/tar.gz/refs/tags/${TAG}"
# GitHub tarball top-level folder: lucene-solr-<tag with slashes replaced by hyphens>
TOP="lucene-solr-$(echo "${TAG}" | tr / -)"
PREFIX="${TOP}/solr/server/solr/configsets/_default/conf"

TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

echo "Merging Solr _default resources from apache/lucene-solr tag ${TAG} -> ${OUT}"
curl -fsSL "${ARCHIVE_URL}" | tar xz -C "${TMP}" \
  "${PREFIX}/lang" \
  "${PREFIX}/stopwords.txt" \
  "${PREFIX}/synonyms.txt" \
  "${PREFIX}/protwords.txt"

SRC="${TMP}/${PREFIX}"
cp -a "${SRC}/lang" "${OUT}/"
cp -a "${SRC}/stopwords.txt" "${SRC}/synonyms.txt" "${SRC}/protwords.txt" "${OUT}/"
echo "Added lang/, stopwords.txt, synonyms.txt, protwords.txt (IQSS schema.xml/solrconfig.xml unchanged)."
