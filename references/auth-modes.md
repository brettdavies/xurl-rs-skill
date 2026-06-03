# Authentication modes

`xr` supports four auth paths and picks per-request based on what's staged in the token store and the environment. This
file describes each path, when to use it, and how to verify it.

> **Verify, don't guess.** Run `xr auth status --output json` to see what's actually configured before reaching for a
> flow.

## The four paths

| Path                   | Command to set up                      | When used                                     | Surface                                   |
| ---------------------- | -------------------------------------- | --------------------------------------------- | ----------------------------------------- |
| OAuth2 PKCE (browser)  | `xr auth oauth2`                       | Desktop with a browser; user-scoped endpoints | All v2 user-scoped endpoints              |
| OAuth2 PKCE (headless) | `xr auth oauth2 --no-browser --step …` | SSH / containers / CI                         | Same as above                             |
| OAuth1 (HMAC-SHA1)     | `xr auth oauth1`                       | v1.1 + some v2 write paths                    | Legacy + a few v2 ops the API still gates |
| Bearer (app-only)      | `xr auth app --bearer-token "$TOKEN"`  | Read-only v2 + search                         | Read-only v2 endpoints + search           |

The CLI picks per request:

- If a Bearer is staged and the endpoint accepts app-auth, Bearer is used.
- Otherwise the user-scoped tokens for the active app drive the call.
- Multi-app: `--app <name>` (or `XURL_APP=<name>`) overrides which app's credentials run the call.
- `--auth <oauth1|oauth2|app>` forces a specific path when the default would pick wrong.

## OAuth2 PKCE — browser flow (the default for humans)

```bash
xr auth oauth2
```

`xr` opens the browser, the user grants scopes, the loopback callback finalizes the exchange, the access and refresh
tokens land in `~/.xurl`. Done.

If multiple apps are registered, `xr` uses the default app unless `--app <name>` is passed. Set the default with `xr
auth default <name>` (or run `xr auth default` for an interactive picker).

Optional positional `<USERNAME>`: skips the `/2/users/me` lookup at the end (saves one API call when the user already
knows which account they're authenticating).

## OAuth2 PKCE — headless flow (the default for agents)

When stdout is not a TTY (piped runs, CI), `--no-browser` auto-engages. To use it explicitly:

```bash
# Step 1 — emit the auth URL.
xr auth oauth2 --no-browser --step 1

# User opens that URL in any browser, completes the grant, copy-pastes the redirect URL back.

# Step 2 — exchange. Use `-` to read the redirect URL from stdin (recommended on shared machines).
echo "<paste redirect URL>" | xr auth oauth2 --no-browser --step 2 --auth-url -
```

The two-step shape is the only safe path for agents driving a remote machine. Never `--auth-url` on the command line on
a multi-user host — the URL contains the authorization code, which shell history will store.

Override the default with `XURL_NO_BROWSER=1` on hosts that should never attempt to open a browser.

## OAuth1

```bash
xr auth oauth1   # interactive prompt for consumer key + consumer secret + token + token secret
```

Required when a verb hits a v1.1 endpoint or one of the few v2 paths the API still gates behind OAuth1 (some media, some
legacy read paths). Tokens persist in `~/.xurl` under the active app. The CLI auto-selects OAuth1 when the endpoint
requires it; pass `--auth oauth1` to force it.

## Bearer (app-only)

```bash
xr auth app --bearer-token "$XURL_BEARER_TOKEN"
# or:
XURL_BEARER_TOKEN="$(op read op://...)" xr search "rustlang" --auth app
```

For read-only v2 endpoints and search. Cannot post, like, follow, etc. — `xr` returns `reason: "auth-required"` if you
try.

## Multi-app management

```bash
# Register an app.
xr auth apps add my-app --client-id "$ID" --client-secret "$SECRET"

# List, update, remove.
xr auth apps list --output json
xr auth apps update my-app --client-secret "$NEW_SECRET"
xr auth apps remove my-app

# Set default app for new shells.
xr auth default my-app             # by name
xr auth default                    # interactive picker

# Per-request override (no default change).
xr --app my-app /2/users/me --output json
```

Each app carries its own per-user OAuth2 tokens and its own OAuth1 keys.

The OAuth2 redirect URI is per-app and configurable:

```bash
xr auth apps redirect-uri my-app                 # inspect
xr auth apps redirect-uri my-app --set "<URI>"   # set (must match the app's registered URI in X's developer portal)
```

## Verifying auth state

```bash
xr auth status --output json
```

Reports, per app:

- Which OAuth modes have tokens staged.
- Active default app and user.
- Token expiry timestamps.
- Whether a refresh token is present (so the CLI can rotate transparently).

When OAuth feels broken, this is the first call to make. It does not hit the X API.

## Clearing tokens

```bash
xr auth clear              # clears tokens for the active app/user
xr auth clear --app my-app # clears for a specific app
```

Use this before re-running a flow if `xr auth status` shows stale or corrupt entries.

## Token store

YAML at `~/.xurl`. Multi-app, with transparent format migration on every load. Don't hand-edit it — use `xr auth ...`
commands. If the file is corrupt, back it up and run `xr auth clear` plus a fresh `xr auth oauth2`.

## Where to find scope and grant details

`xr` does not enumerate the X-API-side scope catalog. Scopes change with OAuth2 client configuration in X's developer
portal, and the authoritative list lives at
<https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code.md> (append `.md` for agent-friendly
markdown).

When a verb returns `reason: "auth-required"` after a successful auth flow, the most likely cause is a missing scope in
the OAuth2 app configuration — not a `xr` bug. Have the user grant the additional scope in the developer portal, re-run
the OAuth2 flow, and re-try.
