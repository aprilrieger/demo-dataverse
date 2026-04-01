#!/bin/bash

# AWS S3 file store for Dataverse.
# https://guides.dataverse.org/en/latest/installation/config.html#s3-storage
#
# Sourced by the base image entrypoint from /opt/payara/scripts/init.d/ *before* Payara starts.
# `asadmin create-jvm-options` cannot run here (DAS is not up on :4848). We append
# `create-system-properties` lines to POSTBOOT_COMMANDS_FILE like init_2_configure.sh.
#
# Requires env: aws_bucket_name, aws_endpoint_url, aws_s3_profile, aws_s3_region (chart sets these when awsS3.enabled).
# Kubernetes: chart sets AWS_SHARED_CREDENTIALS_FILE / AWS_CONFIG_FILE (mounted Secret).
# Compose (often root): copy credentials into ~/.aws when those vars are unset.

if [ -n "${aws_bucket_name:-}" ]; then
    if [ -z "${AWS_SHARED_CREDENTIALS_FILE:-}" ] && [ -r /secrets/aws-cli/.aws/credentials ]; then
        if mkdir -p /root/.aws 2>/dev/null; then
            cp -R /secrets/aws-cli/.aws/. /root/.aws/
        else
            _aws_dir="${HOME:-/opt/payara}/.aws"
            mkdir -p "$_aws_dir" || { _aws_dir="/opt/payara/.aws" && mkdir -p "$_aws_dir"; }
            cp -R /secrets/aws-cli/.aws/. "${_aws_dir}/"
        fi
    fi

    if [ -z "${POSTBOOT_COMMANDS_FILE:-}" ] || [ ! -w "$POSTBOOT_COMMANDS_FILE" ]; then
        echo "006-s3-aws-storage: POSTBOOT_COMMANDS_FILE missing or not writable" >&2
        return 1
    fi

    # Keep dataverse.files.local.* so the "local" driver stays registered for existing DB rows that still
    # reference that storage identifier. Set default uploads to S3 via storage-driver-id=S3 only.
    # Strip prior S3.* and storage-driver-id lines so pod restarts do not duplicate properties.
    _pb_pre=$(mktemp)
    _pb_dep=$(mktemp)
    trap 'rm -f "${_pb_pre:-}" "${_pb_dep:-}"' EXIT
    grep -v -E '^create-system-properties dataverse\.files\.storage-driver-id=' "$POSTBOOT_COMMANDS_FILE" \
        | grep -v -E '^create-system-properties dataverse\.files\.S3\.' \
        | grep -v -E '^deploy ' > "$_pb_pre" || true
    grep -E '^deploy ' "$POSTBOOT_COMMANDS_FILE" > "$_pb_dep" || true
    _ep=$(printf '%s' "${aws_endpoint_url}" | sed -e 's/:/\\\:/g')
    # With custom-endpoint-url set, Dataverse's S3AccessIO uses JVM key custom-endpoint-region for SigV4.
    # If unset, upstream defaults to the literal string "dataverse" → S3 400 "region 'dataverse' is wrong".
    _s3_reg="${aws_s3_region:-${AWS_REGION:-}}"
    if [ -z "${_s3_reg}" ]; then
        echo "006-s3-aws-storage: set aws_s3_region (Helm awsS3.region) or AWS_REGION when using custom-endpoint-url" >&2
        return 1
    fi
    {
        cat "$_pb_pre"
        echo "create-system-properties dataverse.files.S3.type=s3"
        echo "create-system-properties dataverse.files.S3.label=S3"
        echo "create-system-properties dataverse.files.S3.bucket-name=${aws_bucket_name}"
        echo "create-system-properties dataverse.files.S3.download-redirect=true"
        echo "create-system-properties dataverse.files.S3.url-expiration-minutes=120"
        echo "create-system-properties dataverse.files.S3.connection-pool-size=4096"
        echo "create-system-properties dataverse.files.storage-driver-id=S3"
        echo "create-system-properties dataverse.files.S3.profile=${aws_s3_profile}"
        echo "create-system-properties dataverse.files.S3.custom-endpoint-url=${_ep}"
        echo "create-system-properties dataverse.files.S3.custom-endpoint-region=${_s3_reg}"
        cat "$_pb_dep"
    } > "$POSTBOOT_COMMANDS_FILE"
    trap - EXIT
    rm -f "$_pb_pre" "$_pb_dep"
    # Payara is not listening yet; set via Admin UI/API after first boot if needed.
    curl -sfS -m 2 -X PUT "http://127.0.0.1:8080/api/admin/settings/:DownloadMethods" -d "native/http" 2>/dev/null || true
fi
