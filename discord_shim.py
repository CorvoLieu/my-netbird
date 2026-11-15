"""Userinfo shim for Dex: decides which Discord users may log in to NetBird.

Dex calls this instead of Discord's /users/@me. Access rules, strictest first:

  DISCORD_CHANNEL_ID set        -> user must be able to SEE that channel
                                   (needs DISCORD_BOT_TOKEN, bot in the server)
  DISCORD_ALLOWED_ROLE_IDS set  -> user must have at least one of those roles
  neither                       -> user must be a member of DISCORD_GUILD_ID

Allowed users get groups: "discord-member" plus "discord-role-<id>" per role,
which NetBird can sync if JWT group sync is enabled.
"""
import json
import os
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

API = "https://discord.com/api/v10"
GUILD_ID = os.environ["DISCORD_GUILD_ID"]
CHANNEL_ID = os.environ.get("DISCORD_CHANNEL_ID", "").strip()
BOT_TOKEN = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
ALLOWED_ROLES = {r.strip() for r in os.environ.get("DISCORD_ALLOWED_ROLE_IDS", "").split(",") if r.strip()}

ADMINISTRATOR = 1 << 3
VIEW_CHANNEL = 1 << 10

if CHANNEL_ID and not BOT_TOKEN:
    raise SystemExit("DISCORD_CHANNEL_ID needs DISCORD_BOT_TOKEN")


def discord_get(path, auth):
    req = urllib.request.Request(API + path, headers={
        "Authorization": auth,
        "User-Agent": "dex-discord-shim/1.1",  # Discord blocks the default Python UA
    })
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)


def can_view_channel(user_id, member_roles, guild, roles, channel):
    """Discord's permission algorithm: base role perms, then channel overwrites."""
    if user_id == guild["owner_id"]:
        return True
    role_perms = {r["id"]: int(r["permissions"]) for r in roles}
    perms = role_perms.get(GUILD_ID, 0)  # @everyone role id == guild id
    for rid in member_roles:
        perms |= role_perms.get(rid, 0)
    if perms & ADMINISTRATOR:
        return True

    overwrites = {o["id"]: o for o in channel.get("permission_overwrites", [])}

    def apply(allow, deny):
        nonlocal perms
        perms = (perms & ~deny) | allow

    everyone = overwrites.get(GUILD_ID)
    if everyone:
        apply(int(everyone["allow"]), int(everyone["deny"]))

    allow = deny = 0
    for rid in member_roles:
        o = overwrites.get(rid)
        if o:
            allow |= int(o["allow"])
            deny |= int(o["deny"])
    apply(allow, deny)

    own = overwrites.get(user_id)
    if own:
        apply(int(own["allow"]), int(own["deny"]))

    return bool(perms & VIEW_CHANNEL)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return self.reply(401, {"error": "missing token"})
        try:
            user = discord_get("/users/@me", auth)
        except urllib.error.HTTPError as e:
            return self.reply(502, {"error": f"discord returned {e.code}"})
        except Exception:
            return self.reply(502, {"error": "could not reach discord"})
        name = f"{user.get('username')} ({user.get('id')})"

        # Membership + roles, using the user's own token (scope: guilds.members.read)
        try:
            member = discord_get(f"/users/@me/guilds/{GUILD_ID}/member", auth)
        except urllib.error.HTTPError as e:
            if e.code in (403, 404):
                return self.deny(name, "not in server")
            return self.reply(502, {"error": f"discord returned {e.code}"})
        except Exception:
            return self.reply(502, {"error": "could not reach discord"})
        member_roles = member.get("roles", [])

        if CHANNEL_ID:
            bot = f"Bot {BOT_TOKEN}"
            try:
                guild = discord_get(f"/guilds/{GUILD_ID}", bot)
                roles = discord_get(f"/guilds/{GUILD_ID}/roles", bot)
                channel = discord_get(f"/channels/{CHANNEL_ID}", bot)
            except urllib.error.HTTPError as e:
                print(f"ERROR   bot lookup failed with {e.code} - is the bot in the server and can it see the channel?", flush=True)
                return self.reply(502, {"error": "bot lookup failed"})
            except Exception:
                return self.reply(502, {"error": "could not reach discord"})
            if not can_view_channel(user["id"], member_roles, guild, roles, channel):
                return self.deny(name, "cannot see channel")
        elif ALLOWED_ROLES and not ALLOWED_ROLES.intersection(member_roles):
            return self.deny(name, "missing required role")

        print(f"ALLOWED {name}", flush=True)
        user["groups"] = ["discord-member"] + [f"discord-role-{r}" for r in member_roles]
        self.reply(200, user)

    def deny(self, name, reason):
        print(f"DENIED  {name} - {reason}", flush=True)
        return self.reply(403, {"error": reason})

    def reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass  # keep logs to the ALLOWED/DENIED lines


if __name__ == "__main__":
    mode = "channel" if CHANNEL_ID else "role" if ALLOWED_ROLES else "membership"
    print(f"discord-shim starting, access mode: {mode}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()