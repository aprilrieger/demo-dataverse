#!/bin/bash

# AWS S3 file store for Dataverse (Payara JVM options).
# https://guides.dataverse.org/en/latest/installation/config.html#s3-storage
#
# Sourced by the base image entrypoint from /opt/payara/scripts/init.d/ before Payara starts.
# Requires env: aws_bucket_name, aws_endpoint_url, aws_s3_profile (chart sets these when awsS3.enabled).
# Requires volume: /secrets/aws-cli/.aws/{credentials,config} (chart mounts aws-cli Secret).

if [ -n "${aws_bucket_name:-}" ]; then
    mkdir -p /root/.aws
    cp -R /secrets/aws-cli/.aws/. /root/.aws/
    asadmin --user="${ADMIN_USER}" --passwordfile="${PASSWORD_FILE}" create-jvm-options "-Ddataverse.files.S3.type\=s3"
    asadmin --user="${ADMIN_USER}" --passwordfile="${PASSWORD_FILE}" create-jvm-options "-Ddataverse.files.S3.label\=S3"
    asadmin --user="${ADMIN_USER}" --passwordfile="${PASSWORD_FILE}" create-jvm-options "-Ddataverse.files.S3.bucket-name\=${aws_bucket_name}"
    asadmin --user="${ADMIN_USER}" --passwordfile="${PASSWORD_FILE}" create-jvm-options "-Ddataverse.files.S3.download-redirect\=true"
    asadmin --user="${ADMIN_USER}" --passwordfile="${PASSWORD_FILE}" create-jvm-options "-Ddataverse.files.S3.url-expiration-minutes\=120"
    asadmin --user="${ADMIN_USER}" --passwordfile="${PASSWORD_FILE}" create-jvm-options "-Ddataverse.files.S3.connection-pool-size\=4096"
    asadmin --user="${ADMIN_USER}" --passwordfile="${PASSWORD_FILE}" create-jvm-options "-Ddataverse.files.storage-driver-id\=S3"
    asadmin --user="${ADMIN_USER}" --passwordfile="${PASSWORD_FILE}" create-jvm-options "-Ddataverse.files.S3.profile\=${aws_s3_profile}"
    asadmin --user="${ADMIN_USER}" --passwordfile="${PASSWORD_FILE}" create-jvm-options "-Ddataverse.files.S3.custom-endpoint-url\=${aws_endpoint_url}"
    # Payara is not listening yet during init.d; set via Admin UI/API after first boot if needed.
    curl -sfS -m 2 -X PUT "http://127.0.0.1:8080/api/admin/settings/:DownloadMethods" -d "native/http" 2>/dev/null || true
fi
