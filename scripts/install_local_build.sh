#!/bin/zsh

set -euo pipefail

if (( $# != 1 )); then
  print -u2 "Usage: scripts/install_local_build.sh /path/to/Topher.app"
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

if [[ ! -d "$source_bundle" ]]; then
  print -u2 "Topher bundle not found: $source_bundle"
  exit 66
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$source_bundle"
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
