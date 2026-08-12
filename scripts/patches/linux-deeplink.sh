#!/usr/bin/env bash
#===============================================================================
# linux-deeplink.sh -- fix `wispr-flow:` deep-link handling on Linux in the
# Wispr Flow main bundle (.webpack/main/index.js).
#
# WHY THIS PATCH EXISTS
# ---------------------
# Wispr Flow registers itself as the `wispr-flow:` protocol handler
# (setAsDefaultProtocolClient("wispr-flow")) and routes inbound deep links to a
# dispatcher (the minified `L(...)`). There are THREE delivery paths:
#
#   * macOS  -> the `open-url` Electron event (handled, platform-correct).
#   * already-running app -> the `second-instance` event scans the new
#       instance's argv for a `wispr-flow:` URL. Its scan is win32-gated, so
#       Linux focuses the existing window but drops the URL payload.
#   * COLD START (app not yet running) -> on Windows AND Linux the OS launches
#       the app with the `wispr-flow:` URL appended to process.argv. The bundle
#       parses it out at startup with:
#
#         if(<isWin32>){
#           const e=B(process.argv.find(e=>
#             e.startsWith("wispr-flow:")||e.startsWith("wispr-flow/")));
#           e&&L(e);
#         }
#
#       This block is gated to win32 ONLY. macOS doesn't need it (it uses
#       open-url), but Linux DOES -- Linux delivers protocol URLs via argv just
#       like Windows. So launching from a `wispr-flow:` link while the app is
#       NOT running silently drops the URL on Linux.
#
# Confirmed against the shipped minified bytes (extract/.../main/index.js):
#   ...quitting"),void e.app.quit();if(f.H8){const e=B(process.argv.find(
#       e=>e.startsWith("wispr-flow:")||e.startsWith("wispr-flow/")));e&&L(e)}
#       e.app.on("second-instance",(t,r)=>{ ...
# where `f.H8` resolves to the win32 flag (`H8:()=>c` with
# `c="win32"===process.platform`; cf. `d.H8?"windows":d.tD?"macos"` and the
# `tD`=darwin flag used by helper-resolver.sh). `process.argv.find` occurs
# EXACTLY ONCE in the whole bundle, so it uniquely pins the cold-start site.
# The second-instance site is pinned separately by its preserved event name and
# the handler argv variable captured from that event.
#
# THE PATCH (surgical, two delivery sites and one route)
# ------------------------------------------------------
# Widen the win32 guard at both URL-delivery sites so Linux is included:
#
#   if(f.H8){const e=B(process.argv.find(...
#     becomes
#   if(f.H8||"linux"===process.platform){/*...COLD_START*/const e=B(...
#
# Cold start anchors on the unique `process.argv.find`. Warm start first derives
# the second-instance handler's argv variable, then anchors on that variable's
# `find` call plus the scheme literal. Both guards derive their minified win32
# accessor from the match. No unrelated Squirrel/registry gate is touched.
#
# The existing `open/Settings/Language` special case gives us a stable route
# anchor. Beside it we add `open/Settings/Shortcuts`, dispatching the app's own
# `OpenShortcutsDialog` event so shortcut capture and conflict checks stay in
# Wispr Flow instead of being duplicated by Linux desktop integration.
#
# Usage: linux-deeplink.sh [path-to-.webpack/main/index.js]
#===============================================================================
set -euo pipefail

BUNDLE="${1:-}"
if [[ -z "$BUNDLE" ]]; then
	# default to the in-repo extracted bundle
	BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	BUNDLE="$BUNDLE/extract/app/.webpack/main/index.js"
fi

if [[ ! -f "$BUNDLE" ]]; then
	echo "ERROR: bundle not found: $BUNDLE" >&2
	exit 1
fi

# --- Idempotency guard --------------------------------------------------------
COLD_MARKER="WISPR_LINUX_DEEPLINK_COLD_START"
SECOND_MARKER="WISPR_LINUX_DEEPLINK_SECOND_INSTANCE"
SHORTCUTS_MARKER="WISPR_LINUX_DEEPLINK_SHORTCUTS_ROUTE"
if grep -q 'WISPR_LINUX_DEEPLINK' "$BUNDLE"; then
	if grep -q "$COLD_MARKER" "$BUNDLE" \
		&& grep -q "$SECOND_MARKER" "$BUNDLE" \
		&& grep -q "$SHORTCUTS_MARKER" "$BUNDLE"; then
		echo "Already patched (all deep-link markers present in $BUNDLE)."
		exit 0
	fi
	echo "ERROR: partial or superseded deep-link patch found in $BUNDLE." >&2
	echo "       Restore the unpatched bundle before reapplying." >&2
	exit 1
fi

# --- Backup -------------------------------------------------------------------
if [[ ! -f "$BUNDLE.orig" ]]; then
	cp -p "$BUNDLE" "$BUNDLE.orig"
	echo "Backup written: $BUNDLE.orig"
fi

# --- Patch (win32 flag accessor DERIVED, not hardcoded) -----------------------
# The minified win32 accessor (`f.H8` today) churns between releases, so each
# site reads it back out of its own match.
python3 - "$BUNDLE" "$COLD_MARKER" "$SECOND_MARKER" \
	"$SHORTCUTS_MARKER" <<'PY'
import sys, io, re
path, cold_marker, second_marker, shortcuts_marker = sys.argv[1:]
with io.open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
    data = f.read()

# Anchor: the cold-start win32 guard immediately followed by the argv scan for
# the wispr-flow: URL. Capture the win32 flag accessor (obj.prop) so we widen
# THIS guard only, never any other site that shares the flag.
#
#   if(<winflag>){const <v>=<B>(process.argv.find(<a>=>
#       <a>.startsWith("wispr-flow:")
cold_anchor = re.compile(
    r'if\((?P<flag>[\w$]+(?:\.[\w$]+)?)\)\{'        # if(<winflag>){
    r'const\s+[\w$]+='                              #   const <v>=
    r'[\w$]+\('                                     #   <B>(
    r'process\.argv\.find\('                        #   process.argv.find(
    r'(?P<a>[\w$]+)=>'                              #     <a>=>
    r'(?P=a)\.startsWith\("wispr-flow:"\)'          #     <a>.startsWith("wispr-flow:")
)
cold_matches = list(cold_anchor.finditer(data))
if len(cold_matches) != 1:
    sys.exit(
        f"ERROR: expected exactly 1 cold-start argv deep-link guard, "
        f"found {len(cold_matches)}. The bundle layout may have changed; "
        f"inspect manually around `process.argv.find`."
    )

# Derive the second-instance handler's argv parameter from the preserved event
# name. This keeps the later argv scan anchored even when minified names churn.
handler_anchor = re.compile(
    r'\.on\("second-instance",\('
    r'(?P<event>[\w$]+),(?P<argv>[\w$]+)\)=>\{'
)
handler_matches = list(handler_anchor.finditer(data))
if len(handler_matches) != 1:
    sys.exit(
        f"ERROR: expected exactly 1 second-instance handler, found "
        f"{len(handler_matches)}. The bundle layout may have changed; inspect "
        f"around the `second-instance` event."
    )

argv = re.escape(handler_matches[0].group('argv'))
second_anchor = re.compile(
    r'if\((?P<flag>[\w$]+(?:\.[\w$]+)?)\)\{'
    r'const\s+[\w$]+='
    r'[\w$]+\('
    + argv + r'\.find\('
    r'(?P<a>[\w$]+)=>'
    r'(?P=a)\.startsWith\("wispr-flow:"\)'
)
second_matches = list(second_anchor.finditer(data))
if len(second_matches) != 1:
    sys.exit(
        f"ERROR: expected exactly 1 second-instance argv deep-link guard, "
        f"found {len(second_matches)}. The bundle layout may have changed; "
        f"inspect around the handler argv `find`."
    )

# Add a Shortcuts sibling beside the existing Language special route. Capture
# the dispatch function, hub window, event namespace, and subpage variable from
# the preserved Language route so no minified identifier is hardcoded.
route_anchor = re.compile(
    r'(?P<language>'
    r'if\("Language"===(?P<subpage>[\w$]+)\)'
    r'(?P<dispatch>\(0,[\w$]+\.[\w$]+\)\()'
    r'(?P<hub>[\w$]+(?:\.[\w$]+)*\.hubWindow),'
    r'(?P<events>[\w$]+(?:\.[\w$]+)*)\.OpenSettings,'
    r'\{page:"General",forceDialog:"language"\}\)'
    r');else'
)
route_matches = list(route_anchor.finditer(data))
if len(route_matches) != 1:
    sys.exit(
        f"ERROR: expected exactly 1 Settings/Language special route, found "
        f"{len(route_matches)}. The bundle layout may have changed; inspect "
        f"around `forceDialog:\"language\"`."
    )

# Widen the guard: insert the linux clause and the marker right after the `{`
# that opens the win32-gated block. Build with concatenation so no `$N`/`$&`
# sequence can be eaten by a replacement DSL (we use a lambda anyway).
def widen(m, marker):
    head = m.group(0)
    open_brace = head.index('){') + 1   # position of `)` before `{`
    # head[:open_brace] == 'if(<flag>)'  ; head[open_brace:] == '{const ...'
    return (
        'if(' + m.group('flag') + '||"linux"===process.platform)'
        '{/*' + marker + '*/'
        + head[open_brace + 1:]          # skip the original '{'
    )

data, cold_n = cold_anchor.subn(
    lambda m: widen(m, cold_marker), data, count=1
)
data, second_n = second_anchor.subn(
    lambda m: widen(m, second_marker), data, count=1
)
def add_shortcuts_route(m):
    return (
        m.group('language')
        + ';else if("Shortcuts"===' + m.group('subpage')
        + '/*' + shortcuts_marker + '*/)'
        + m.group('dispatch') + m.group('hub') + ','
        + m.group('events') + '.OpenShortcutsDialog)'
        + ';else'
    )

data, route_n = route_anchor.subn(add_shortcuts_route, data, count=1)
if cold_n != 1 or second_n != 1 or route_n != 1:
    sys.exit(
        f"ERROR: substitutions applied cold={cold_n}, "
        f"second-instance={second_n}, shortcuts-route={route_n} times "
        f"(expected 1 each)."
    )

with io.open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
    f.write(data)
print(
    "Patched: cold-start and second-instance argv guards widened to include "
    "linux; Settings/Shortcuts route added (1 site each)."
)
PY

# --- Verify the result --------------------------------------------------------
if ! grep -q "$COLD_MARKER" "$BUNDLE" \
	|| ! grep -q "$SECOND_MARKER" "$BUNDLE" \
	|| ! grep -q "$SHORTCUTS_MARKER" "$BUNDLE"; then
	echo "ERROR: post-patch verification failed (marker missing)." >&2
	echo "       Restoring backup." >&2
	cp -p "$BUNDLE.orig" "$BUNDLE"
	exit 1
fi

for marker in "$COLD_MARKER" "$SECOND_MARKER"; do
	if ! grep -q \
		'"linux"===process.platform){/\*'"$marker"'\*/const' \
		"$BUNDLE"; then
		echo "ERROR: $marker not adjacent to its argv guard." >&2
		echo "       Restoring backup." >&2
		cp -p "$BUNDLE.orig" "$BUNDLE"
		exit 1
	fi
done

if ! grep -qP \
	'/\*'"$SHORTCUTS_MARKER"'\*/\)\(0,[\w$]+\.[\w$]+\)\([\w$.]+\.hubWindow,[\w$.]+\.OpenShortcutsDialog\)' \
	"$BUNDLE"; then
	echo "ERROR: Shortcuts route not in expected form. Restoring backup." >&2
	cp -p "$BUNDLE.orig" "$BUNDLE"
	exit 1
fi

# Syntax-check: catch a replacement that serializes but doesn't parse before it
# ever reaches asar.
if command -v node >/dev/null; then
	if ! node --check "$BUNDLE"; then
		echo "ERROR: node --check failed on patched bundle. Restoring backup." >&2
		cp -p "$BUNDLE.orig" "$BUNDLE"
		exit 1
	fi
	echo "node --check OK"
fi

echo "OK: Linux cold-start and second-instance deep-link guards widened"
echo "    in $BUNDLE"
echo
echo "Patched cold and warm starts now do (conceptually):"
echo "  if (isWin32 || process.platform === 'linux') {"
echo "    const url = argv.find(a => a.startsWith('wispr-flow:'));"
echo "    if (url) dispatchDeepLink(url);"
echo "  }"
echo
echo "Linux now delivers the URL whether Flow is stopped or already running."
echo "Settings/Shortcuts opens Flow's native shortcut recorder."
echo "macOS continues to use its open-url event."
