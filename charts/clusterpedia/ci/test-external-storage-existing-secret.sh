#!/usr/bin/env bash

set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered_dir="$(mktemp -d)"
trap 'rm -rf "$rendered_dir"' EXIT

external_args=(
  --set persistenceMatchNode=None
  --set storageInstallMode=external
  --set mysql.enabled=false
  --set postgresql.enabled=false
)
secret_args=(
  --set externalStorage.dsn.secretKeyRef.name=dce5-kpanda-creds
  --set externalStorage.dsn.secretKeyRef.key=DATABASE_DSN
)

render_existing_secret() {
  local storage_type="$1"
  local create_database="$2"
  local output="$rendered_dir/${storage_type}-${create_database}.yaml"

  helm template test "$chart_dir" \
    "${external_args[@]}" \
    "${secret_args[@]}" \
    --set "externalStorage.type=${storage_type}" \
    --set "externalStorage.createDatabase=${create_database}" > "$output"

  test "$(grep -c 'name: DB_DSN' "$output")" -eq 4
  test "$(grep -c 'name: dce5-kpanda-creds' "$output")" -eq 4
  test "$(grep -c 'key: DATABASE_DSN' "$output")" -eq 4
  grep -q '^    dsn: ""$' "$output"
}

render_existing_secret mysql false
render_existing_secret mysql true
render_existing_secret postgres false
render_existing_secret postgres true

plaintext_dsn='user:password@tcp(database.example.com:3306)/clusterpedia'
helm template test "$chart_dir" \
  "${external_args[@]}" \
  --set externalStorage.type=mysql \
  --set-string "externalStorage.dsn=${plaintext_dsn}" > "$rendered_dir/plaintext.yaml"
grep -Fq "dsn: \"${plaintext_dsn}\"" "$rendered_dir/plaintext.yaml"
! grep -q 'name: DB_DSN' "$rendered_dir/plaintext.yaml"

if helm template test "$chart_dir" \
  "${external_args[@]}" \
  --set externalStorage.type=mysql \
  --set externalStorage.dsn.secretKeyRef.name=dce5-kpanda-creds > /dev/null 2>&1; then
  echo "expected an existing Secret without a key to be rejected" >&2
  exit 1
fi
