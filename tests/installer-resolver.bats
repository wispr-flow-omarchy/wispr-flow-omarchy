#!/usr/bin/env bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../scripts/setup/resolve-installer-url.sh"

setup() {
	TEST_TMP=$(mktemp -d)
	manifest="$TEST_TMP/latest.json"
}

teardown() {
	if [[ -n ${TEST_TMP:-} && -d $TEST_TMP ]]; then
		rm -rf "$TEST_TMP"
	fi
}

write_manifest() {
	local url="$1" checksum="$2"
	cat > "$manifest" <<JSON
{
  "schemaVersion": 1,
  "windows": {
    "x64": {
      "url": "$url",
      "sha256": "$checksum",
      "size": 354737528
    }
  }
}
JSON
}

@test "installer resolver reads the official manifest contract" {
	write_manifest \
		"https://example.test/Wispr%20Flow%20Setup-v1.6.606.exe" \
		"0000000000000000000000000000000000000000000000000000000000000000"

	run "$RESOLVER" --latest-url "file://$manifest"
	[[ $status -eq 0 ]]
	[[ $output == *"URL=https://example.test/Wispr%20Flow%20Setup-v1.6.606.exe"* ]]
	[[ $output == *"VERSION=1.6.606"* ]]
	[[ $output == *"SHA256=0000000000000000000000000000000000000000000000000000000000000000"* ]]
}

@test "installer resolver constructs the pinned supported URL" {
	run "$RESOLVER" --version 1.6.7
	[[ $status -eq 0 ]]
	[[ $output == *"URL=https://dl.wisprflow.com/wispr-flow/win32/x64/Wispr%20Flow%20Setup-v1.6.7.exe"* ]]
	[[ $output == *"VERSION=1.6.7"* ]]
}

@test "installer resolver rejects an invalid checksum" {
	write_manifest \
		"https://example.test/Wispr%20Flow%20Setup-v1.6.606.exe" \
		"not-a-checksum"

	run "$RESOLVER" --latest-url "file://$manifest"
	[[ $status -ne 0 ]]
	[[ $output == *"invalid Wispr Flow installer checksum"* ]]
}

@test "installer resolver rejects an unversioned payload" {
	write_manifest \
		"https://example.test/WisprFlowInstaller.exe" \
		"0000000000000000000000000000000000000000000000000000000000000000"

	run "$RESOLVER" --latest-url "file://$manifest"
	[[ $status -ne 0 ]]
	[[ $output == *"could not parse a version"* ]]
}
