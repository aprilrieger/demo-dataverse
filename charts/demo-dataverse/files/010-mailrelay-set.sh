#!/bin/bash

# Setup mail relay (compose-compatible; mounted when values.mail.enabled).
# https://guides.dataverse.org/en/latest/developers/troubleshooting.html
#
# smtp_enabled: false|0|no skips this script (GitHub vars SMTP_ENABLED).
# smtp_type=plain implies SMTP AUTH after STARTTLS if smtp_auth is unset (Rails-style).
# smtp_auth / smtp_starttls: true|1|yes when set explicitly.
case "${smtp_enabled}" in
    false|0|no|NO|False) exit 0 ;;
esac

if [ "${system_email}" ]; then
    curl -X PUT -d ${system_email} http://localhost:8080/api/admin/settings/:SystemEmail
    asadmin --user=${ADMIN_USER} --passwordfile=${PASSWORD_FILE} delete-javamail-resource mail/notifyMailSession

    AUTH_PROP="mail.smtp.auth=false"
    case "${smtp_auth}" in
        true|1|yes|TRUE|Yes) AUTH_PROP="mail.smtp.auth=true" ;;
    esac
    if [ "${AUTH_PROP}" = "mail.smtp.auth=false" ]; then
        case "${smtp_type}" in
            plain|PLAIN) AUTH_PROP="mail.smtp.auth=true" ;;
        esac
    fi

    PROPS="${AUTH_PROP}:mail.smtp.password=${smtp_password}:mail.smtp.port=${smtp_port}:mail.smtp.socketFactory.port=${socket_port}:mail.smtp.socketFactory.fallback=false"
    case "${smtp_starttls}" in
        true|1|yes|TRUE|Yes) PROPS="${PROPS}:mail.smtp.starttls.enable=true" ;;
    esac

    asadmin --user=${ADMIN_USER} --passwordfile=${PASSWORD_FILE} create-javamail-resource --mailhost ${mailhost} --mailuser ${mailuser} --fromaddress ${no_reply_email} --property "${PROPS}" mail/notifyMailSession
fi
