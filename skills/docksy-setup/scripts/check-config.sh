#!/bin/zsh
set -eu

if (( $# != 2 )); then
    print -u2 'Usage: check-config.sh REPOSITORY_DIRECTORY CANDIDATE_JSON'
    exit 64
fi
docksy_repo_root="${1:A}"
docksy_candidate="${2:A}"
[[ -f "$docksy_repo_root/Sources/Configuration.swift" ]] || { print -u2 'Docksy configuration source not found.'; exit 1; }
[[ -f "$docksy_candidate" ]] || { print -u2 'Candidate settings file not found.'; exit 1; }

docksy_check_dir=$(mktemp -d "${TMPDIR:-/tmp}/docksy-config-check.XXXXXX")
trap 'rm -rf -- "$docksy_check_dir"' EXIT
cat > "$docksy_check_dir/main.swift" <<'SWIFT'
import Foundation
do {
    let config = try Configuration.load(from: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("Valid Docksy settings (\(config.databaseTargets.count) database targets).")
} catch {
    fputs("Invalid Docksy settings: \(error)\n", stderr)
    exit(1)
}
SWIFT
xcrun swiftc -module-cache-path "$docksy_check_dir/module-cache" \
    "$docksy_repo_root/Sources/Configuration.swift" "$docksy_check_dir/main.swift" -o "$docksy_check_dir/check-config"
"$docksy_check_dir/check-config" "$docksy_candidate"
