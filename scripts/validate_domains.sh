#!/bin/bash

# Validate domains in the raw file via a variety of checks and flag entries
# that require attention.

readonly FUNCTION='bash scripts/tools.sh'
readonly RAW='data/raw.txt'
readonly RAW_LIGHT='data/raw_light.txt'
readonly WHITELIST='config/whitelist.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly REVIEW_CONFIG='config/review_config.csv'
readonly ROOT_DOMAINS='data/root_domains.txt'
readonly SUBDOMAINS='data/subdomains.txt'
readonly SUBDOMAINS_TO_REMOVE='config/subdomains.txt'
readonly DOMAIN_REGEX='[[:alnum:]][[:alnum:].-]*[[:alnum:]]\.[[:alnum:]-]*[a-z]{2,}[[:alnum:]-]*'

main() {
    $FUNCTION --download-toplist

    $FUNCTION --update-review-config

    validate
}

# Remove entries from the raw file and log the entries into the domain log.
# Input:
#   $1: entries to process passed in a variable
#   $2: tag to be shown in the domain log
#   --preserve: keep entries in the raw file
# Output:
#   filter_log.tmp (if filtered domains found)
filter() {
    local entries="$1"
    local tag="$2"

    # Return if no entries passed
    [[ -z "$entries" ]] && return

    if [[ "$3" == '--preserve' ]]; then
        # Save entries into review config file
        mawk -v reason="$tag" \
            '{ print "raw," $0 "," reason ",," }' <<< "$entries" \
            >> "$REVIEW_CONFIG"
        # Remove duplicates
        mawk '!seen[$0]++' "$REVIEW_CONFIG" > temp
        mv temp "$REVIEW_CONFIG"
    else
        # Remove entries from raw file
        comm -23 "$RAW" <(printf "%s" "$entries") > temp
        mv temp "$RAW"
    fi

    # Record entries into filter log for console output
    mawk -v tag="$tag" '{ print $0 " (" tag ")" }' <<< "$entries" \
        >> filter_log.tmp

    $FUNCTION --log-domains "$entries" "$tag" raw
}

# Validate raw file.
validate() {
    # Convert Unicode to Punycode in raw file and raw light file
    $FUNCTION --convert-unicode "$RAW"
    $FUNCTION --convert-unicode "$RAW_LIGHT"

    # Strip away subdomains
    while read -r subdomain; do  # Loop through common subdomains
        subdomains="$(mawk "/^${subdomain}\./" "$RAW")"

        # Continue if no subdomains found
        [[ -z "$subdomains" ]] && continue

        # Strip subdomains from raw file and raw light file
        sed -i "s/^${subdomain}\.//" "$RAW"
        sed -i "s/^${subdomain}\.//" "$RAW_LIGHT"

        # Save subdomains and root domains to be filtered later
        printf "%s\n" "$subdomains" >> subdomains.tmp
        printf "%s\n" "$subdomains" | sed "s/^${subdomain}\.//" \
            >> root_domains.tmp
    done < "$SUBDOMAINS_TO_REMOVE"
    sort -u "$RAW" -o "$RAW"
    sort -u "$RAW_LIGHT" -o "$RAW_LIGHT"

    # Remove whitelisted domains excluding blacklisted domains
    # Note whitelist matching uses regex matching
    filter \
        "$(grep -Ef "$WHITELIST" "$RAW" | grep -vxFf "$BLACKLIST")" whitelist

    # Remove domains with whitelisted TLDs excluding blacklisted domains
    filter \
        "$(awk '/\.(gov|edu|mil)(\.[a-z]{2})?$/' "$RAW" \
        | grep -vxFf "$BLACKLIST")" whitelisted_tld

    # Remove non-domain entries including IP addresses excluding Punycode
    filter "$(awk "!/^${DOMAIN_REGEX}$/" "$RAW")" invalid

    # Find domains in toplist excluding blacklisted domains
    # Note the toplist does not include subdomains
    filter \
        "$(comm -12 toplist.tmp "$RAW" | grep -vxFf "$BLACKLIST")" \
            toplist --preserve

    # Return if no filtering done
    [[ ! -f filter_log.tmp ]] && return

    # Save filtered subdomains and root domains into the subdomains and root
    # domains files.
    if [[ -f root_domains.tmp ]]; then
        sort -u root_domains.tmp -o root_domains.tmp

        # Keep only root domains present in the final filtered domains
        comm -12 root_domains.tmp "$RAW" > temp
        mv temp root_domains.tmp

        # Collate filtered root domains
        sort -u root_domains.tmp "$ROOT_DOMAINS" -o "$ROOT_DOMAINS"

        # Collate filtered subdomains
        grep -f root_domains.tmp subdomains.tmp \
            | sort -u - "$SUBDOMAINS" -o "$SUBDOMAINS"
    fi

    # Save changes to raw light file
    comm -12 "$RAW_LIGHT" "$RAW" > temp
    mv temp "$RAW_LIGHT"

    # Print filter log
    printf "\n\e[1mProblematic domains (%s):\e[0m\n" "$(wc -l < filter_log.tmp)"
    sed 's/(toplist)/& - \o033[31mmanual verification required\o033[0m/' filter_log.tmp

    [[ ! -s filter_log.tmp ]] && return

    $FUNCTION --send-telegram \
        "Validation: problematic domains found\n\n$(<filter_log.tmp)"

    printf "\nTelegram notification sent.\n"
}

# Entry point

set -e

trap 'rm ./*.tmp temp 2> /dev/null || true' EXIT

$FUNCTION --format-files

main
