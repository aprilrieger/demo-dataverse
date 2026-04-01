#!/bin/bash

# AWS S3 file store for Dataverse (Payara JVM options).
# https://guides.dataverse.org/en/latest/installation/config.html#s3-storage
#
# Sourced by the base image entrypoint from /opt/payara/scripts/init.d/ before Payara starts.
# Requires env: aws_bucket_name, aws_endpoint_url, aws_s3_profile (chart sets these when awsS3.enabled).
# Requires volume: /secrets/aws-cli/.aws/{credentials,config} (chart mounts aws-cli Secret).
#
# Kubernetes (non-root): chart sets AWS_SHARED_CREDENTIALS_FILE / AWS_CONFIG_FILE → no copy.
# Compose (often root): copy into ~/.aws when those vars are unset.

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
    # init_1_change_passwords.sh runs with `set -u` and does not define ADMIN_USER / PASSWORD_FILE.
    # Official image uses PAYARA_ADMIN_USER / PAYARA_ADMIN_PASSWORD (see gdcc base image).
    _dv_asadmin_user="${ADMIN_USER:-${PAYARA_ADMIN_USER:-admin}}"
    _dv_asadmin_pwfile=$(mktemp)
    trap 'rm -f "${_dv_asadmin_pwfile:-}"' EXIT
    printf 'AS_ADMIN_PASSWORD=%s\n' "${PAYARA_ADMIN_PASSWORD:-admin}" >"$_dv_asadmin_pwfile"
    asadmin --user="$_dv_asadmin_user" --passwordfile="$_dv_asadmin_pwfile" create-jvm-options "-Ddataverse.files.S3.type\=s3"
    asadmin --user="$_dv_asadmin_user" --passwordfile="$_dv_asadmin_pwfile" create-jvm-options "-Ddataverse.files.S3.label\=S3"
    asadmin --user="$_dv_asadmin_user" --passwordfile="$_dv_asadmin_pwfile" create-jvm-options "-Ddataverse.files.S3.bucket-name\=${aws_bucket_name}"
    asadmin --user="$_dv_asadmin_user" --passwordfile="$_dv_asadmin_pwfile" create-jvm-options "-Ddataverse.files.S3.download-redirect\=true"
    asadmin --user="$_dv_asadmin_user" --passwordfile="$_dv_asadmin_pwfile" create-jvm-options "-Ddataverse.files.S3.url-expiration-minutes\=120"
    asadmin --user="$_dv_asadmin_user" --passwordfile="$_dv_asadmin_pwfile" create-jvm-options "-Ddataverse.files.S3.connection-pool-size\=4096"
    asadmin --user="$_dv_asadmin_user" --passwordfile="$_dv_asadmin_pwfile" create-jvm-options "-Ddataverse.files.storage-driver-id\=S3"
    asadmin --user="$_dv_asadmin_user" --passwordfile="$_dv_asadmin_pwfile" create-jvm-options "-Ddataverse.files.S3.profile\=${aws_s3_profile}"
    asadmin --user="$_dv_asadmin_user" --passwordfile="$_dv_asadmin_pwfile" create-jvm-options "-Ddataverse.files.S3.custom-endpoint-url\=${aws_endpoint_url}"
    trap - EXIT
    rm -f "$_dv_asadmin_pwfile"
    # Payara is not listening yet during init.d; set via Admin UI/API after first boot if needed.
    curl -sfS -m 2 -X PUT "http://127.0.0.1:8080/api/admin/settings/:DownloadMethods" -d "native/http" 2>/dev/null || true
fi
