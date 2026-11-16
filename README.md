# my-netbird
my netbird instance

## Secrets (Bitwarden)

Bitwarden is the single source of truth: no secrets or IDs are stored in this repo
and there is no `.env` file. `make run` unlocks your vault, loads everything, and
starts the stack.

1. On the server, install the [Bitwarden CLI](https://bitwarden.com/help/cli/) and `jq`, then run `bw login` once.
2. In Bitwarden, create one item named **`netbird`** (a Secure Note is fine) with these
   custom fields (type "Hidden"):

   custom fields. Put only the value in the value box (e.g. name `DISCORD_GUILD_ID`,
   value `123456789012345678`), not `NAME=value`.

   | Field                      | Required | Value                                                    |
   |----------------------------|----------|----------------------------------------------------------|
   | `DISCORD_CLIENT_ID`        | yes      | Discord app → OAuth2 → Client ID                         |
   | `DISCORD_CLIENT_SECRET`    | yes      | Discord app → OAuth2 → Client Secret                     |
   | `DISCORD_GUILD_ID`         | yes      | your Discord server ID                                   |
   | `NETBIRD_RELAY_SECRET`     | yes      | `openssl rand -base64 32`                                |
   | `TURN_PASSWORD`            | yes      | `openssl rand -base64 32`                                |
   | `NETBIRD_DATASTORE_KEY`    | yes      | `openssl rand -base64 32` — **never change once in use** |
   | `DISCORD_CHANNEL_ID`       | no       | only users who can see this channel may log in           |
   | `DISCORD_BOT_TOKEN`        | no       | needed if `DISCORD_CHANNEL_ID` is set                    |
   | `DISCORD_ALLOWED_ROLE_IDS` | no       | comma-separated role IDs (used when no channel is set)   |

   Use type "Hidden" for the secrets; the IDs can be "Text". Leave optional fields out
   (or empty) to skip that check.

3. `make run` (asks for your master password), `make stop` to stop.

`management.json.tmpl` is the NetBird config; the real file is written to
`.secrets/management.json` (git-ignored, owner-only) on each `make run`.
