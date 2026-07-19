#!/bin/zsh

set -euo pipefail

reset_accessibility=false
if (( $# == 2 )) && [[ "$1" == "--reset-accessibility" ]]; then
  reset_accessibility=true
  shift
fi

if (( $# != 1 )); then
  print -u2 "Usage: scripts/install_local_build.sh [--reset-accessibility] /path/to/Topher.app"
  exit 64
fi

source_bundle="$1"
destination_bundle="/Applications/Topher.app"
staging_bundle="${destination_bundle}.installing.$$"
backup_bundle="${destination_bundle}.previous.$$"

cleanup_install() {
  local exit_code="$1"
  trap - EXIT
  /bin/rm -rf "$staging_bundle"
  if (( exit_code != 0 )) && [[ -e "$backup_bundle" ]]; then
    /bin/rm -rf "$destination_bundle"
    /bin/mv "$backup_bundle" "$destination_bundle"
    /usr/bin/open "$destination_bundle" 2>/dev/null || true
  fi
  /bin/rm -rf "$backup_bundle"
  exit "$exit_code"
}

trap 'cleanup_install $?' EXIT

topher_instance_count() {
  local output
  local -a process_ids
  output=$(/usr/bin/pgrep -x Topher 2>/dev/null || true)
  if [[ -z "$output" ]]; then
    print 0
    return
  fi
  process_ids=("${(@f)output}")
  print "${#process_ids}"
}

designated_requirement() {
  /usr/bin/codesign -dr - "$1" 2>&1 \
    | /usr/bin/sed -n 's/^# designated => //p'
}

if [[ ! -d "$source_bundle" ]]; then
  print -u2 "Topher bundle not found: $source_bundle"
  exit 66
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$source_bundle"
bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$source_bundle/Contents/Info.plist")
if [[ "$bundle_identifier" != "dev.topher.app" ]]; then
  print -u2 "Unexpected Topher bundle identifier: $bundle_identifier"
  exit 65
fi

source_requirement=$(designated_requirement "$source_bundle")
if [[ -z "$source_requirement" ]]; then
  print -u2 "Unable to read Topher's designated code requirement."
  exit 65
fi
installed_requirement=""
if [[ -d "$destination_bundle" ]]; then
  installed_requirement=$(designated_requirement "$destination_bundle")
fi
accessibility_identity_changed=false
if [[ -n "$installed_requirement" && "$installed_requirement" != "$source_requirement" ]]; then
  accessibility_identity_changed=true
fi

/bin/rm -rf "$staging_bundle" "$backup_bundle"
/usr/bin/ditto --rsrc --extattr --acl "$source_bundle" "$staging_bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$staging_bundle"

/usr/bin/pkill -x Topher 2>/dev/null || true
for _ in {1..20}; do
  if ! /usr/bin/pgrep -x Topher >/dev/null; then
    break
  fi
  sleep 0.1
done

if /usr/bin/pgrep -x Topher >/dev/null; then
  print -u2 "Topher did not stop cleanly; installation aborted."
  exit 70
fi

if [[ -e "$destination_bundle" ]]; then
  /bin/mv "$destination_bundle" "$backup_bundle"
fi
/bin/mv "$staging_bundle" "$destination_bundle"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$destination_bundle"

if $reset_accessibility; then
  /usr/bin/tccutil reset Accessibility "$bundle_identifier"
  print "Reset Topher's Accessibility grant; macOS will require explicit approval again."
elif $accessibility_identity_changed; then
  print -u2 "Warning: Topher's code requirement changed. An existing Accessibility row may look enabled but remain stale."
  print -u2 "If dictation is denied, reinstall once with --reset-accessibility, then allow Topher again."
fi

/usr/bin/open "$destination_bundle"

for _ in {1..50}; do
  instance_count=$(topher_instance_count)
  if [[ "$instance_count" == "1" ]]; then
    break
  fi
  sleep 0.1
done

instance_count=$(topher_instance_count)
if [[ "$instance_count" != "1" ]]; then
  print -u2 "Expected one running Topher process, found $instance_count."
  exit 70
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$destination_bundle/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$destination_bundle/Contents/Info.plist")
/bin/rm -rf "$backup_bundle"
print "Installed and launched Topher $version ($build) with one active process."
