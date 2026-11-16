#!/bin/sh
# Loads all settings and secrets from Bitwarden, renders management.json, then runs the given command.
#   Usage: sh with-secrets.sh docker compose up -d
#
# Everything lives as custom fields on one Bitwarden vault item (default name "netbird",
# override with BW_ITEM). See README.md for the field list.
set -eu

ITEM="${BW_ITEM:-netbird}"
REQUIRED="DISCORD_CLIENT_ID DISCORD_CLIENT_SECRET DISCORD_GUILD_ID NETBIRD_RELAY_SECRET TURN_PASSWORD NETBIRD_DATASTORE_KEY"
OPTIONAL="DISCORD_BOT_TOKEN DISCORD_CHANNEL_ID DISCORD_ALLOWED_ROLE_IDS"

die() { echo "with-secrets: $*" >&2; exit 1; }

command -v bw >/dev/null || die "Bitwarden CLI 'bw' not found (https://bitwarden.com/help/cli/)"
command -v jq >/dev/null || die "'jq' not found (apt install jq)"

case "$(bw status | jq -r .status)" in
  unauthenticated) die "not logged in - run 'bw login' once first" ;;
  locked)
    BW_SESSION="$(bw unlock --raw)" || die "unlock failed"
    export BW_SESSION
    ;;
esac

bw sync >/dev/null
item="$(bw get item "$ITEM")" || die "vault item '$ITEM' not found"

field() {
  printf '%s' "$item" | jq -er --arg n "$1" '.fields[]? | select(.name == $n) | .value // empty'
}

for name in $REQUIRED; do
  value="$(field "$name")" || die "field '$name' is missing or empty on item '$ITEM'"
  export "$name=$value"
done
for name in $OPTIONAL; do
  value="$(field "$name")" || value=""
  export "$name=$value"
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
