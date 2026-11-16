# my-netbird
my netbird instance

## Secrets (Bitwarden Secrets Manager)

Bitwarden Secrets Manager is the single source of truth: no secrets or IDs are stored
in this repo and there is no `.env` file. `make run` uses a machine account to load
everything and starts the stack. No master password is involved.

1. **Project.** In your Bitwarden organization, open Secrets Manager (the free plan is
   enough) and create a project named `netbird`.
2. **Secrets.** In that project, add one secret per row below. The secret's **name**
   is the variable name and its **value** is just the value (e.g. name
   `DISCORD_GUILD_ID`, value `123456789012345678`).

   | Name                       | Required | Value                                                    |
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

   Leave optional secrets out to skip that check.

3. **Machine account.** Create a machine account (e.g. `netbird-server`), give it
   **Can read** access to the `netbird` project only, and create an access token for
   it. Copy the token; it is only shown once.
4. **Server.** Install the [Secrets Manager CLI](https://bitwarden.com/help/secrets-manager-cli/)
   (`bws`) and `jq`, then save the token in the repo folder:

   ```sh
   mkdir -p .secrets && chmod 700 .secrets
   (umask 077; cat > .secrets/bws-token)   # paste the token, press Enter, then Ctrl-D
   ```

   (Pasting into `cat` keeps the token out of your shell history.)

   (Or pass it as `BWS_ACCESS_TOKEN`, or point `BWS_TOKEN_FILE` at another file.)
   EU-region accounts also need `export BWS_SERVER_URL=https://vault.bitwarden.eu`.
5. `make run` to start, `make stop` to stop.

Secrets are loaded only from the project named `netbird`, found by name. Use
`BWS_PROJECT=<name>` for a different name, or `BWS_PROJECT_ID=<uuid>` to skip the
lookup (the ID is the long code shown by `bws project list`, not the name).

`management.json.tmpl` is the NetBird config; the real file is written to
`.secrets/management.json` (git-ignored, owner-only) on each `make run`.

To change a secret, edit it in Secrets Manager and run `make run` again.
