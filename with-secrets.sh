#!/bin/sh
# Loads all settings and secrets from Bitwarden Secrets Manager, renders
# management.json, then runs the given command.
#   Usage: sh with-secrets.sh docker compose up -d
#
# Each secret's name in Secrets Manager is the env var name (e.g. TURN_PASSWORD).
# The machine account's access token is read from $BWS_ACCESS_TOKEN, or from
# $BWS_TOKEN_FILE (default .secrets/bws-token). Secrets are loaded from the project
# named $BWS_PROJECT (default "netbird"), or set BWS_PROJECT_ID to its ID. See README.md.
set -eu

REQUIRED="DISCORD_CLIENT_ID DISCORD_CLIENT_SECRET DISCORD_GUILD_ID NETBIRD_RELAY_SECRET TURN_PASSWORD NETBIRD_DATASTORE_KEY"
# Optional (left empty if not in Secrets Manager): DISCORD_BOT_TOKEN DISCORD_CHANNEL_ID DISCORD_ALLOWED_ROLE_IDS

die() { echo "with-secrets: $*" >&2; exit 1; }
quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

cd "$(dirname "$0")"

# Phase 1: re-run this script under `bws run`, which adds the secrets to the environment.
if [ -z "${_NB_SECRETS_LOADED:-}" ]; then
  command -v bws >/dev/null || die "Bitwarden Secrets Manager CLI 'bws' not found (https://bitwarden.com/help/secrets-manager-cli/)"
  if [ -z "${BWS_ACCESS_TOKEN:-}" ]; then
    token_file="${BWS_TOKEN_FILE:-.secrets/bws-token}"
    [ -r "$token_file" ] || die "no access token: set BWS_ACCESS_TOKEN or create $token_file"
    BWS_ACCESS_TOKEN="$(tr -d '\r\n' < "$token_file")"
    export BWS_ACCESS_TOKEN
  fi
  command -v jq >/dev/null || die "'jq' not found (apt install jq)"

  # Find the project's ID from its name, unless an ID was given.
  if [ -z "${BWS_PROJECT_ID:-}" ]; then
    project="${BWS_PROJECT:-netbird}"
    projects="$(bws project list --output json)" || die "could not list projects (wrong token, or EU account without BWS_SERVER_URL?)"
    BWS_PROJECT_ID="$(printf '%s' "$projects" | jq -r --arg n "$project" '[.[] | select(.name == $n)][0].id // empty')"
    if [ -z "$BWS_PROJECT_ID" ]; then
      visible="$(printf '%s' "$projects" | jq -r '[.[].name] | join(", ")')"
      die "machine account can't see a project named '$project' (it can see: ${visible:-nothing}). Give it access to the project in Secrets Manager → Machine accounts → Projects."
    fi
  fi

  export _NB_SECRETS_LOADED=1
  cmd="sh $(quote "$(basename "$0")")"   # we already cd'd into the script's directory
  for arg in "$@"; do cmd="$cmd $(quote "$arg")"; done
  exec bws run --project-id "$BWS_PROJECT_ID" -- "$cmd"
fi

# Phase 2: secrets are in the environment.
unset BWS_ACCESS_TOKEN _NB_SECRETS_LOADED   # don't pass the token on to docker/containers
command -v jq >/dev/null || die "'jq' not found (apt install jq)"

for name in $REQUIRED; do
  eval "value=\${$name:-}"
  [ -n "$value" ] || die "secret '$name' is missing in Secrets Manager (or the machine account can't read it)"
done

# NetBird management can't read env vars, so write a filled-in copy (owner-only, git-ignored).
umask 077
mkdir -p .secrets
jq --arg relay "$NETBIRD_RELAY_SECRET" \
   --arg turn "$TURN_PASSWORD" \
   --arg key "$NETBIRD_DATASTORE_KEY" \
   '.Relay.Secret = $relay
    | .TURNConfig.Turns[0].Password = $turn
    | .DataStoreEncryptionKey = $key' \
   management.json.tmpl > .secrets/management.json

"$@"
