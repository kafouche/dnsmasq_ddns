#!/bin/sh

set -o errexit
set -o nounset
set -o pipefail

# PREREQUISITES

if [ -z "${1}" ]; then
    printf 'E: Missing Action.\n' >&2
    exit 1
fi

case "${1}" in
  add|old)
    ;;
  *)
    exit 0
    ;;
esac

if [ -z "${3}" ]; then
    printf 'E: Missing IP Address.\n' >&2
    exit 1
fi

if [ -z "${4}" ]; then
    printf 'E: Missing Hostname.\n' >&2
    exit 1 
fi

# FUNCTIONS

function add_record
{
    local zone="${1}"
    local record="${2}"
    local ttl="${3}"
    local type="${4}"
    local data="${5}"

    printf 'zone %s\n' "${zone}"
    printf 'update delete %s %s\n' "${record}" "${type}"
    printf 'update add %s %s %s %s\n' "${record}" "${ttl}" "${type}" "${data}"
    printf 'show\n'
    printf 'send\n'
    printf '\n'
}

function get_domain
{
    if [ ! -z "${DOMAIN}" ]; then
        printf '%s' "${DOMAIN}"
    elif [ ! -z "${DNSMASQ_DOMAIN}" ]; then
        printf '%s' "${DNSMASQ_DOMAIN}"
    else
        printf 'E: Missing DOMAIN!\n'
        exit 1
    fi
}

function get_record
{
    local is_reverse="${1}"
    local record="${2}"
    local domain="${3}"

    if [ "${is_reverse}" -eq 1 ]; then
        printf '%s.in-addr.arpa.' "${record}"
    else
        printf '%s.%s.' "${record}" "${DOMAIN}"
    fi
}

function get_reverse_ipaddress
{
    local ipaddr="${1}"

    printf '%s' "${ipaddr}" | awk -F. '{print $4"."$3"."$2"."$1}'
}

function get_reverse_zone
{
    local ipaddr="${1}"

    local reverse_zone="$(printf '%s' "${ipaddr}" | awk -F. '{print $3"."$2"."$1}')"

    printf '%s.in-addr.arpa' "${reverse_zone}"
}


# MAIN

readonly SCPATH="$(dirname "$(readlink -f "${0}")")"

. "${SCPATH}/dnsmasq_ddns.conf"

ddns_dir="${SCPATH}/dnsmasq_ddns.d"
log_file="${SCPATH}/dnsmasq_ddns.log"

domain="$(get_domain)"
hostname="${4}"
ipaddr="${3}"
reverse_ipaddr="$(get_reverse_ipaddress "${ipaddr}")"
reverse_zone="$(get_reverse_zone "${ipaddr}")"

mkdir --parents "${ddns_dir}"

# MASTER DNS SERVER
printf 'server %s\n' "${SERVER}" > "${ddns_dir}/${hostname}.txt"

# ZONE UPDATE
data="${ipaddr}"
record="$(get_record 0 "${hostname}" "${domain}")"
add_record "${domain}" "${record}" "${TTL}" "${TYPE}" "${data}" \
    >> "${ddns_dir}/${hostname}.txt"

# REVERSE ZONE UPDATE
data="${record}"
record="$(get_record 1 "${reverse_ipaddr}" "${domain}")"
add_record "${reverse_zone}" "${record}" "${TTL}" "${REVERSE_TYPE}" "${data}" \
    >> "${ddns_dir}/${hostname}.txt"


# UPDATE BIND9 RECORDS
nsupdate -k "${SCPATH}/${KEY_FILE}" -v "${ddns_dir}/${hostname}.txt"

# LOG
printf '%s: Record %s.%s (%s) updated.\n' \
    "$(date '+%Y-%M-%d - %H:%m')" "${hostname}" "${domain}" "${ipaddr}" \
    >> "${log_file}"

exit 0