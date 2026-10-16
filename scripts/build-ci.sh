#!/bin/bash
# A dedicated read-only dependency key, never the developer's personal SSH key.
set -euo pipefail
if [[ -z "${IOS_BASE_DEPLOY_KEY:-}" ]]; then
  echo '::error::Missing IOS_BASE_READONLY_DEPLOY_KEY. Fork PRs receive no repository secrets; validate native builds on a trusted maintainer branch.'
  exit 1
fi
umask 077
task_ssh_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/yuji-ci-ssh.XXXXXX")"
cleanup() {
  rm -f "$task_ssh_dir/key" "$task_ssh_dir/meta.json" "$task_ssh_dir/known_hosts"
  rmdir "$task_ssh_dir"
}
trap cleanup EXIT
printf '%s\n' "$IOS_BASE_DEPLOY_KEY" > "$task_ssh_dir/key"
unset IOS_BASE_DEPLOY_KEY
ssh-keygen -y -f "$task_ssh_dir/key" > /dev/null
# Fetch host keys over authenticated TLS instead of trusting ssh-keyscan output.
# The job's existing read-only token avoids shared-runner anonymous API limits.
curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
  -H "Authorization: Bearer ${GH_TOKEN:?Missing read-only job token}" \
  https://api.github.com/meta > "$task_ssh_dir/meta.json"
unset GH_TOKEN
node - "$task_ssh_dir/meta.json" "$task_ssh_dir/known_hosts" <<'NODE'
const fs = require('fs');
const keys = JSON.parse(fs.readFileSync(process.argv[2], 'utf8')).ssh_keys;
if (!Array.isArray(keys) || !keys.length || keys.some(k => !/^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) [A-Za-z0-9+/=]+$/.test(k))) {
  throw new Error('Invalid GitHub SSH host key metadata');
}
fs.writeFileSync(process.argv[3], keys.map(k => `github.com ${k}\n`).join(''));
NODE
export GIT_SSH_COMMAND="ssh -i '$task_ssh_dir/key' -o IdentitiesOnly=yes -o UserKnownHostsFile='$task_ssh_dir/known_hosts' -o StrictHostKeyChecking=yes"
xcodebuild build-for-testing -project ios-app/Yuji.xcodeproj -scheme Yuji \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build-ci \
  -scmProvider system CODE_SIGNING_ALLOWED=NO
