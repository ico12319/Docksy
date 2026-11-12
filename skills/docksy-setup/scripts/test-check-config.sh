#!/bin/zsh
set -eu
docksy_script_dir="${0:A:h}"
docksy_repo_root="${docksy_script_dir:h:h:h}"
docksy_fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/docksy-check-unit.XXXXXX")
trap 'rm -rf -- "$docksy_fixture_dir"' EXIT

cp "$docksy_repo_root/examples/config.json" "$docksy_fixture_dir/valid settings.json"
zsh "$docksy_script_dir/check-config.sh" "$docksy_repo_root" "$docksy_fixture_dir/valid settings.json"
cmp "$docksy_repo_root/examples/config.json" "$docksy_fixture_dir/valid settings.json"

cat > "$docksy_fixture_dir/invalid settings.json" <<'JSON'
{"databaseTargets":[{"name":"Test","namespace":"default","resource":"service/db","localPort":70000,"remotePort":5432}]}
JSON
cp "$docksy_fixture_dir/invalid settings.json" "$docksy_fixture_dir/original.json"
if zsh "$docksy_script_dir/check-config.sh" "$docksy_repo_root" "$docksy_fixture_dir/invalid settings.json" > "$docksy_fixture_dir/error.txt" 2>&1; then
    print -u2 'Invalid ports were accepted.'; exit 1
fi
grep -q 'ports must be between 1 and 65535' "$docksy_fixture_dir/error.txt"
cmp "$docksy_fixture_dir/original.json" "$docksy_fixture_dir/invalid settings.json"

if zsh "$docksy_script_dir/check-config.sh" "$docksy_repo_root" "$docksy_fixture_dir/missing.json" > "$docksy_fixture_dir/error.txt" 2>&1; then
    print -u2 'A missing settings file was accepted.'; exit 1
fi
grep -q 'Candidate settings file not found' "$docksy_fixture_dir/error.txt"
print 'Setup checker unit checks passed; no app, kubectl, or live settings were used.'
