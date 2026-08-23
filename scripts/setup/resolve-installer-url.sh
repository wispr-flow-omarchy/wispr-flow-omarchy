#!/usr/bin/env bash
#===============================================================================
# resolve-installer-url.sh -- resolve the latest Wispr Flow Windows installer
# URL, version, and checksum from the upstream release manifest.
#
# Wispr Flow publishes a stable JSON manifest whose x64 entry names the
# versioned installer and its SHA-256 checksum:
#   https://dl.wisprflow.com/wispr-flow/win32/latest.json
#
# Only a Windows x64 build is published (the arm64 Windows endpoint redirects to
# the homepage). The Linux arm64 package is built from the SAME x64 installer --
# the app bundle is arch-neutral JS/asar -- so this resolver is arch-independent.
#
# Output contract (stdout, one KEY=VALUE per line; ALL diagnostics to stderr):
#   URL=<installer download URL>
#   VERSION=<x.y.z extracted from the installer filename>
#   SHA256=<vendor-published checksum>
#
# Usage:   resolve-installer-url.sh [--latest-url <url>] [--version <x.y.z>]
#   --latest-url   override the upstream release manifest endpoint
#   --version      resolve the exact pinned installer instead of latest
#
# Exit 0 on success; non-zero if the URL can't be resolved or the version can't
# be parsed. This is a standalone CI helper -- it sources nothing.
#===============================================================================
set -uo pipefail

readonly DEFAULT_LATEST_URL='https://dl.wisprflow.com/wispr-flow/win32/latest.json'
readonly INSTALLER_BASE_URL='https://dl.wisprflow.com/wispr-flow/win32/x64'

log() { printf '%s\n' "$*" >&2; }
die() { printf 'resolve-installer-url: %s\n' "$*" >&2; exit 1; }

latest_url="$DEFAULT_LATEST_URL"
version_override=''

while [[ $# -gt 0 ]]; do
	case "$1" in
		--latest-url)
			[[ -n ${2:-} ]] || die '--latest-url needs a value'
			latest_url="$2"; shift 2 ;;
		--version)
			[[ ${2:-} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
				|| die '--version needs x.y.z'
			version_override="$2"; shift 2 ;;
		-h|--help)
			grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
		*)
			die "unknown argument: $1" ;;
	esac
done

if [[ -n $version_override ]]; then
	printf 'URL=%s/Wispr%%20Flow%%20Setup-v%s.exe\n' \
		"$INSTALLER_BASE_URL" "$version_override"
	printf 'VERSION=%s\n' "$version_override"
	printf 'SHA256=\n'
	exit 0
fi

command -v curl >/dev/null 2>&1 || die 'curl is required'
command -v python3 >/dev/null 2>&1 || die 'python3 is required'

log "Resolving Wispr Flow installer from ${latest_url} ..."

# Read and validate the vendor manifest. Python's standard JSON parser keeps
# this helper independent of jq and available in every supported build image.
manifest="$(curl -fsSL --max-time 60 "$latest_url")"
rc=$?
if [[ $rc -ne 0 || -z $manifest ]]; then
	die "failed to resolve ${latest_url} (curl rc=${rc})"
fi

resolved="$(python3 -c '
import json
import sys

try:
    item = json.load(sys.stdin)["windows"]["x64"]
    url = item["url"]
    checksum = item["sha256"].lower()
except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
    raise SystemExit(f"invalid Wispr Flow release manifest: {error}")

if not isinstance(url, str) or not url.startswith("https://"):
    raise SystemExit("invalid Wispr Flow installer URL")
if len(checksum) != 64 or any(c not in "0123456789abcdef" for c in checksum):
    raise SystemExit("invalid Wispr Flow installer checksum")

print(f"URL={url}")
print(f"SHA256={checksum}")
' <<< "$manifest")" || die "invalid release manifest from ${latest_url}"

final_url="$(printf '%s\n' "$resolved" | sed -nE 's/^URL=//p')"
sha256="$(printf '%s\n' "$resolved" | sed -nE 's/^SHA256=//p')"
log "Resolved URL: ${final_url}"

# Extract the version from the filename, e.g. "...Setup-v1.5.695.exe" -> 1.5.695.
version="$(printf '%s\n' "$final_url" \
	| sed -nE 's/.*[Ss]etup-v([0-9]+\.[0-9]+\.[0-9]+)\.exe.*/\1/p')"

if [[ -z $version ]]; then
	die "could not parse a version from ${final_url}"
fi

log "Resolved version: ${version}"

printf 'URL=%s\n' "$final_url"
printf 'VERSION=%s\n' "$version"
printf 'SHA256=%s\n' "$sha256"
