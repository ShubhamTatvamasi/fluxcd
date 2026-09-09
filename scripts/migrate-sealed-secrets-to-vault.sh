#!/usr/bin/env bash
#
# Discovers every ExternalSecret manifest under secrets/external-secrets/, finds the
# matching SealedSecret manifest in the mirrored secrets/sealed-secrets/ tree, and
# decrypts it locally with `kubeseal --recovery-unseal` using the sealed-secrets
# controller's private key - then writes that plaintext data into Vault/OpenBao at
# the same remoteRef.key path so the ExternalSecret can resolve against it instead.
#
# This never relies on the live cluster's already-decrypted Secret objects: it
# decrypts the SealedSecret ciphertext itself, offline, so it works purely from the
# recovery private key + the files in this repo. It also never creates or modifies
# files in secrets/external-secrets/ or secrets/sealed-secrets/ - both are read-only
# input, used respectively to learn the secretKey/remoteRef mapping and to locate +
# decrypt the matching ciphertext.
#
# Works against either backend - HashiCorp Vault or OpenBao - since both speak the
# same `vault`/`bao` KV v2 CLI. Everything environment-specific is a flag; defaults
# assume Vault, pass --backend openbao to target this repo's OpenBao deployment.
#
# Usage:
#   ./scripts/migrate-sealed-secrets-to-vault.sh [options]
#
#   --dry-run                 Print what would be written, don't call the backend.
#   --recovery-key PATH        Sealed-secrets controller recovery private key, as produced
#                              by `kubeseal --fetch-cert` / a backed-up controller key Secret
#                              (default: ~/myfiles/office/portainer/sealed-secrets/sealed-secrets-key.yaml).
#
#   --backend vault|openbao    Which CLI binary + default env var names to use (default: vault).
#   --pod-namespace NS         Namespace the Vault/OpenBao pod runs in (default: vault; --backend openbao defaults this to openbao unless overridden).
#   --pod NAME                 Pod to exec the CLI in (default: vault-0; --backend openbao defaults this to openbao-vault-0 unless overridden).
#   --container NAME           Container within that pod (default: vault).
#   --kv-mount PATH            KV v2 mount path (default: secret).
#
#   --token-secret NAME        K8s Secret holding the root/write token (default: bank-vaults).
#   --token-secret-namespace NS  Namespace of that Secret (default: same as --pod-namespace).
#   --token-secret-key KEY     Key within that Secret's data (default: vault-root).
#
# Note on --token-secret: the bank-vaults/vault-root default matches this repo's
# OpenBao deployment (the bank-vaults operator stores its generated root token
# there). A plain HashiCorp Vault install has no universal equivalent - there is
# no standard convention for where a Vault root/write token lives as a K8s Secret,
# so --backend vault will very likely need --token-secret(-namespace/-key) set
# explicitly to match however that cluster's Vault was bootstrapped.
#
# Requires: kubeseal, kubectl (pointed at the target cluster, used only to reach
# Vault/OpenBao - never to read application secrets), yq, jq.
# The Vault/OpenBao token is read fresh immediately before every single write
# (bank-vaults rotates it periodically) and piped into the pod over stdin - it is
# never placed on a command line, in shell history, or in a file on this machine.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTERNAL_SECRETS_DIR="${REPO_ROOT}/secrets/external-secrets"
SEALED_SECRETS_DIR="${REPO_ROOT}/secrets/sealed-secrets"
WORK_DIR="${TMPDIR:-/tmp}/secret-migrate-$$"

RECOVERY_KEY="${HOME}/myfiles/office/portainer/sealed-secrets/sealed-secrets-key.yaml"

BACKEND="vault"
POD_NAMESPACE="vault"
POD_NAME="vault-0"
CONTAINER="vault"
KV_MOUNT="secret"

TOKEN_SECRET_NAME="bank-vaults"
TOKEN_SECRET_NAMESPACE=""
TOKEN_SECRET_KEY="vault-root"

# Track whether the user explicitly passed pod/token flags, so backend-specific
# defaults (below) only kick in for values they didn't override themselves.
POD_NAMESPACE_SET=false
POD_NAME_SET=false

DRY_RUN=false

# ---------------------------------------------------------------------------
# Functions (all defined before use, then invoked in the main body at the end)
# ---------------------------------------------------------------------------

print_help() {
  awk 'NR>1 && /^#/{print substr($0,3); next} NR>1{exit}' "${BASH_SOURCE[0]}"
}

cleanup() {
  rm -rf "$WORK_DIR"
}

# Decrypts a SealedSecret file locally with the recovery private key and prints
# its plaintext `data` as a "key<TAB>base64value" stream, one per line. Never
# touches the cluster - this is pure offline decryption.
decrypt_sealed_secret() {
  local sealed_file="$1"
  local decrypted stderr_output kubeseal_status

  stderr_output="${WORK_DIR}/kubeseal-stderr.$$.log"
  decrypted=$(kubeseal --recovery-unseal \
    --recovery-private-key "$RECOVERY_KEY" \
    --format yaml \
    < "$sealed_file" 2>"$stderr_output")
  kubeseal_status=$?
  if [[ $kubeseal_status -ne 0 ]]; then
    echo "kubeseal failed to decrypt ${sealed_file} (exit ${kubeseal_status}):" >&2
    cat "$stderr_output" >&2
    rm -f "$stderr_output"
    return 1
  fi
  rm -f "$stderr_output"
  yq -r '.data // {} | to_entries | .[] | "\(.key)\t\(.value)"' <<<"$decrypted"
}

# bank-vaults rotates the root token periodically (observed in practice: a token
# fetched at script start can be stale minutes later, causing spurious 403s that
# have nothing to do with actual permissions). So the token is fetched fresh,
# immediately before every single write, never cached across calls.
fetch_backend_token() {
  local token
  token=$(kubectl get secret "$TOKEN_SECRET_NAME" -n "$TOKEN_SECRET_NAMESPACE" -o jsonpath="{.data.${TOKEN_SECRET_KEY}}" | base64 -d)
  if [[ -z "$token" ]]; then
    echo "Could not read token from secret/${TOKEN_SECRET_NAME} key '${TOKEN_SECRET_KEY}' in namespace ${TOKEN_SECRET_NAMESPACE}" >&2
    return 1
  fi
  echo "$token"
}

write_to_backend() {
  local remote_key="$1"
  local json_payload="$2"
  local token

  token=$(fetch_backend_token) || return 1

  # kubectl exec -i only forwards fd 0 (stdin) to the pod, so the token and the
  # JSON payload both travel over that one channel: the token as the first
  # line, the payload as everything after. The remote shell consumes exactly
  # one line with `read` (leaving the rest of stdin untouched for the CLI's own
  # `-` read), so nothing is ever passed as a command-line argument, embedded
  # in the remote command text, or left on disk.
  { printf '%s\n' "$token"; printf '%s' "$json_payload"; } | \
    kubectl exec -i -n "$POD_NAMESPACE" "$POD_NAME" -c "$CONTAINER" -- sh -c '
      command -v '"$CLI_BIN"' >/dev/null 2>&1 || { echo "'"$CLI_BIN"' CLI not found in container" >&2; exit 127; }
      IFS= read -r '"$TOKEN_VAR"'
      export '"$TOKEN_VAR"'
      export '"$ADDR_VAR"'=http://127.0.0.1:8200
      '"$CLI_BIN"' kv put -mount='"$KV_MOUNT"' '"$remote_key"' -
    '
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --recovery-key) RECOVERY_KEY="$2"; shift 2 ;;
    --backend) BACKEND="$2"; shift 2 ;;
    --pod-namespace) POD_NAMESPACE="$2"; POD_NAMESPACE_SET=true; shift 2 ;;
    --pod) POD_NAME="$2"; POD_NAME_SET=true; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    --kv-mount) KV_MOUNT="$2"; shift 2 ;;
    --token-secret) TOKEN_SECRET_NAME="$2"; shift 2 ;;
    --token-secret-namespace) TOKEN_SECRET_NAMESPACE="$2"; shift 2 ;;
    --token-secret-key) TOKEN_SECRET_KEY="$2"; shift 2 ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

case "$BACKEND" in
  vault) CLI_BIN="vault"; ADDR_VAR="VAULT_ADDR"; TOKEN_VAR="VAULT_TOKEN" ;;
  openbao)
    CLI_BIN="bao"; ADDR_VAR="BAO_ADDR"; TOKEN_VAR="BAO_TOKEN"
    # This repo's actual deployment is OpenBao, named/namespaced accordingly -
    # apply those as defaults when the user picked this backend but didn't
    # already override the pod location themselves.
    $POD_NAMESPACE_SET || POD_NAMESPACE="openbao"
    $POD_NAME_SET || POD_NAME="openbao-vault-0"
    ;;
  *) echo "Unknown --backend '$BACKEND' (expected 'vault' or 'openbao')" >&2; exit 1 ;;
esac

[[ -z "$TOKEN_SECRET_NAMESPACE" ]] && TOKEN_SECRET_NAMESPACE="$POD_NAMESPACE"

for bin in kubeseal kubectl yq jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Missing required tool: $bin" >&2; exit 1; }
done

if [[ ! -f "$RECOVERY_KEY" ]]; then
  echo "Sealed-secrets recovery private key not found: ${RECOVERY_KEY}" >&2
  echo "Pass --recovery-key PATH to point at the controller's backed-up private key." >&2
  exit 1
fi

if [[ ! -d "$EXTERNAL_SECRETS_DIR" ]]; then
  echo "ExternalSecret source directory not found: ${EXTERNAL_SECRETS_DIR}" >&2
  echo "This script reads existing ExternalSecret manifests to learn the secretKey/remoteRef mapping - it does not generate them, so it has nothing to migrate without that directory." >&2
  exit 1
fi

if [[ ! -d "$SEALED_SECRETS_DIR" ]]; then
  echo "SealedSecret source directory not found: ${SEALED_SECRETS_DIR}" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"
chmod 700 "$WORK_DIR"
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Discover ExternalSecret -> remoteRef.key mappings, and their matching
# SealedSecret file in the mirrored directory tree
# ---------------------------------------------------------------------------

echo "Scanning ${EXTERNAL_SECRETS_DIR} for ExternalSecret manifests..."
mapfile -t ES_FILES < <(find "$EXTERNAL_SECRETS_DIR" -type f -name '*-externalsecret.yaml' | sort)
echo "Found ${#ES_FILES[@]} ExternalSecret manifests."
if [[ ${#ES_FILES[@]} -eq 0 ]]; then
  echo "Nothing to do."
  exit 0
fi

declare -A KEY_TO_PROPERTIES    # remoteKey -> space-separated "secretKey=property" pairs
declare -A KEY_TO_SEALED_FILE   # remoteKey -> matching SealedSecret file path
declare -A KEY_TO_SOURCE_FILE   # remoteKey -> originating ExternalSecret file, for messages

for f in "${ES_FILES[@]}"; do
  distinct_keys=$(yq -r '[.spec.data[].remoteRef.key] | unique | .[]' "$f")
  key_count=$(echo "$distinct_keys" | grep -c . || true)
  if [[ "$key_count" -eq 0 ]]; then
    echo "  skip (no remoteRef.key): $f"
    continue
  elif [[ "$key_count" -gt 1 ]]; then
    echo "  WARN: $f has multiple distinct remoteRef.key values ($(echo "$distinct_keys" | paste -sd ',' -)) - this script assumes one key per file, only the first will be used" >&2
  fi
  remote_key=$(echo "$distinct_keys" | head -n1)

  es_rel_dir=$(dirname "${f#"$EXTERNAL_SECRETS_DIR"/}")
  sealed_dir="${SEALED_SECRETS_DIR}/${es_rel_dir}"
  mapfile -t sealed_candidates < <(find "$sealed_dir" -maxdepth 1 -name '*-sealedsecret.yaml' 2>/dev/null | sort)
  if [[ ${#sealed_candidates[@]} -eq 0 ]]; then
    echo "  skip (no matching SealedSecret found under ${sealed_dir}): $f"
    continue
  elif [[ ${#sealed_candidates[@]} -gt 1 ]]; then
    echo "  WARN: multiple SealedSecret files under ${sealed_dir}, using the first: ${sealed_candidates[0]}" >&2
  fi

  pairs=$(yq -r '.spec.data[] | "\(.secretKey)=\(.remoteRef.property)"' "$f" | tr '\n' ' ')
  KEY_TO_PROPERTIES["$remote_key"]="$pairs"
  KEY_TO_SEALED_FILE["$remote_key"]="${sealed_candidates[0]}"
  KEY_TO_SOURCE_FILE["$remote_key"]="$f"
done

echo
echo "Resolved ${#KEY_TO_PROPERTIES[@]} distinct secret paths to migrate to ${BACKEND}."
echo "Target: ${BACKEND} (${CLI_BIN}) in pod ${POD_NAMESPACE}/${POD_NAME} (container ${CONTAINER}), kv mount '${KV_MOUNT}'"
echo "Decrypting locally with recovery key: ${RECOVERY_KEY}"
echo

# ---- sanity check the token secret is reachable before starting the loop ----
# (the actual token used for each write is fetched fresh at write time, since
# it can rotate mid-run - see fetch_backend_token.)
if ! $DRY_RUN; then
  fetch_backend_token >/dev/null || exit 1
fi

# ---------------------------------------------------------------------------
# Migrate each discovered key
# ---------------------------------------------------------------------------

TOTAL=0
MIGRATED=0
SKIPPED=0
FAILED=0

for remote_key in "${!KEY_TO_PROPERTIES[@]}"; do
  TOTAL=$((TOTAL + 1))
  sealed_file="${KEY_TO_SEALED_FILE[$remote_key]}"
  src_file="${KEY_TO_SOURCE_FILE[$remote_key]}"
  decrypted_data=""
  json_payload="{}"
  value_b64=""
  value=""

  echo "== ${remote_key} (source: ${sealed_file}) =="

  decrypted_data=$(decrypt_sealed_secret "$sealed_file") || {
    SKIPPED=$((SKIPPED + 1))
    echo
    unset decrypted_data json_payload value_b64 value
    continue
  }

  for pair in ${KEY_TO_PROPERTIES[$remote_key]}; do
    secret_key="${pair%%=*}"
    property="${pair#*=}"
    value_b64=$(awk -F'\t' -v k="$secret_key" '$1==k{print $2; exit}' <<<"$decrypted_data")
    if [[ -z "$value_b64" ]]; then
      echo "  WARN: key '${secret_key}' not present in decrypted ${sealed_file}, skipping property '${property}'"
      continue
    fi
    value=$(echo "$value_b64" | base64 -d)
    json_payload=$(echo "$json_payload" | jq --arg p "$property" --arg v "$value" '. + {($p): $v}')
  done

  if [[ "$json_payload" == "{}" ]]; then
    echo "  SKIP: no matching data keys found in decrypted ${sealed_file}"
    SKIPPED=$((SKIPPED + 1))
    echo
    unset decrypted_data json_payload value_b64 value
    continue
  fi

  if $DRY_RUN; then
    echo "  DRY-RUN: would write to ${BACKEND} ${KV_MOUNT}/${remote_key} with properties: $(echo "$json_payload" | jq -r 'keys | join(", ")')"
  else
    write_log="${WORK_DIR}/$(echo "$remote_key" | tr '/' '_').log"
    if write_to_backend "$remote_key" "$json_payload" >"$write_log" 2>&1; then
      echo "  wrote ${KV_MOUNT}/${remote_key}"
      MIGRATED=$((MIGRATED + 1))
    else
      echo "  FAILED to write ${remote_key}:"
      sed 's/^/    /' "$write_log"
      FAILED=$((FAILED + 1))
    fi
  fi
  # Defense-in-depth: this loop is the only place plaintext secret material
  # exists as shell variables, so drop it as soon as each key is done rather
  # than letting it linger in the process environment for the rest of the run.
  unset decrypted_data json_payload value_b64 value
  echo
done

echo "=================================================="
echo "Total keys discovered : $TOTAL"
if $DRY_RUN; then
  echo "(dry run - nothing written)"
else
  echo "Migrated              : $MIGRATED"
  echo "Skipped                : $SKIPPED"
  echo "Failed                 : $FAILED"
fi
