#!/usr/bin/env bash
set -euo pipefail

mail_root="${HOME}/Library/Mail"
best_path=""
best_version=-1

if [[ ! -d "$mail_root" ]]; then
  printf 'Mail cache directory not found: %s\n' "$mail_root" >&2
  exit 1
fi

for path in "$mail_root"/V*/MailData/"Envelope Index"; do
  [[ -f "$path" && -r "$path" ]] || continue
  version_dir="${path#"$mail_root"/V}"
  version="${version_dir%%/*}"
  [[ "$version" =~ ^[0-9]+$ ]] || continue
  if (( version > best_version )); then
    best_version=$version
    best_path=$path
  fi
done

if [[ -z "$best_path" ]]; then
  printf 'No readable Mail Envelope Index found under %s/V*/MailData\n' "$mail_root" >&2
  exit 1
fi

printf '%s\n' "$best_path"
