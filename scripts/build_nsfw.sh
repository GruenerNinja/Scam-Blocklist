#!/bin/bash

# Build the NSFW blocklist. The build process is entirely self-contained in
# this script.

readonly FUNCTION='bash scripts/tools.sh'
readonly BLOCKLIST='lists/adblock/nsfw.txt'

# Patterns to match for
readonly -a TERMS=(
    porn
    xxx
    spankbang
    xhamster
    xvideos
    onlyfans
    fansly
    hentai
    redtube
    internetchicks
    masterfap
    thothub
    onlyleaks
    thumbzilla
    fapello
    thenudebay
    gonewild
    thothd
    camwhores
    brazzers
    hookup
    ^sex
    \.sex$
    escorts
    rule34
    hookers
    blowjob
    jizz
)

# Whitelisted domains
readonly -a WHITELIST=(
    batteryhookup.com
    sexpistolsofficial.com
    1337xxx.to
)

# Retrieve domains from the Tranco toplist, add them to the
# raw file, format the file and remove dead domains.
build() {
    # Format raw file to Domains format
    mawk '/[|]/ {gsub(/[|^]/, ""); print}' "$BLOCKLIST" > raw.tmp

    # Remove already processed domains
    comm -23 toplist.tmp raw.tmp > temp
    mv temp toplist.tmp

    # Get matching domains in toplist
    local term
    for term in "${TERMS[@]}"; do
        mawk "/${term}/" toplist.tmp >> domains.tmp
    done

    # Add new domains to raw file
    sort -u domains.tmp raw.tmp -o raw.tmp

    # Remove whitelisted domains
    local white
    for white in "${WHITELIST[@]}"; do
        sed -i "/${white}/d" raw.tmp
    done

    # Compile list. See the list of transformations here:
    # https://github.com/AdguardTeam/HostlistCompiler
    printf "\n"
    hostlist-compiler -i raw.tmp -o compiled.tmp

    # Remove dead domains
    printf "\n"
    dead-domains-linter -a -i compiled.tmp

    # Remove comments
    sed -i '/!/d' compiled.tmp
}

# Create the blocklist in Adblock Plus syntax.
deploy() {
    cat << EOF > "$BLOCKLIST"
[Adblock Plus]
! Title: Jarelllama's NSFW Blocklist
! Description: Blocklist for NSFW domains automatically retrieved daily.
! Homepage: https://github.com/jarelllama/Scam-Blocklist#nsfw-blocklist
! License: https://raw.githubusercontent.com/jarelllama/Scam-Blocklist/main/LICENSE.md
! Version: $(date -u +"%m.%d.%H%M%S.%Y")
! Expires: 12 hours
! Last modified: $(date -u)
! Syntax: Adblock Plus
! Number of entries: $(wc -l < compiled.tmp)
!
EOF
    cat compiled.tmp >> "$BLOCKLIST"
}

# Entry point

set -e

trap 'rm ./*.tmp temp 2> /dev/null' EXIT

# Install AdGuard's Dead Domains Linter
if ! command -v dead-domains-linter &> /dev/null; then
    npm install -g @adguard/dead-domains-linter > /dev/null
fi

# Install AdGuard's Hostlist Compiler
if ! command -v hostlist-compiler &> /dev/null; then
    npm install -g @adguard/hostlist-compiler > /dev/null
fi

# Download the Tranco toplist
$FUNCTION --download-toplist

build

deploy
