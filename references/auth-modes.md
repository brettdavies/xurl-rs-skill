# Authentication modes

`xr` supports four auth paths and picks per-request based on what's staged in the token store and the environment. This
file describes each path, when to use it, how to verify it, and how to recover when a verb exits `77`.

> **Verify, don't guess.** Run `xr auth status --output json` to see what's actually configured before reaching for a
> flow. The answer is `{"status":"ok","apps":[...]}`; read it through `.apps[]`. Verified on `xr 4.1.0`.

## The four paths

| Path                   | Command to set up                      | When used                                     | Surface                                   |
| ---------------------- | -------------------------------------- | --------------------------------------------- | ----------------------------------------- |
| OAuth2 PKCE (browser)  | `xr auth oauth2`                       | Desktop with a browser; user-scoped endpoints | All v2 user-scoped endpoints              |
| OAuth2 PKCE (headless) | `xr auth oauth2 --no-browser --step …` | SSH / containers / CI                         | Same as above                             |
| OAuth1 (HMAC-SHA1)     | `xr auth oauth1`                       | v1.1 + some v2 write paths                    | Legacy + a few v2 ops the API still gates |
| Bearer (app-only)      | `xr auth app --bearer-token "$TOKEN"`  | Read-only v2 + search                         | Read-only v2 endpoints + search           |

The CLI picks per request:

- If a Bearer is available (`XURL_BEARER_TOKEN` in the environment wins over a stored one) and the endpoint accepts
  app-auth, Bearer is used.
- Otherwise the user-scoped tokens for the active app drive the call.
- Multi-app: `--app <name>` (or `XURL_APP=<name>`) overrides which app's credentials run the call.
- `--auth <oauth1|oauth2|app>` forces a specific path when the default would pick wrong. Forcing a scheme the endpoint
  rejects answers `reason: "auth-method-mismatch"`, exit `2`, with the accepted schemes in `supported`. Forcing
  `--auth oauth2` on an app that has client credentials but no stored token answers `reason: "auth-required"`, exit
  `77`, with a `sign-in` `next_step`; it never opens a browser mid-request.

## What `auth status` returns

```bash
xr auth status --output json
```

```json
{
  "status": "ok",
  "apps": [
    {
      "name": "my-app",
      "client_id_hint": "abcdefgh",
      "default": true,
      "oauth2_users": ["alice"],
      "oauth1": false,
      "bearer": true,
      "bearer_source": "store",
      "redirect_uri": "http://localhost:8080/callback",
      "redirect_uri_source": "built-in-default"
    }
  ]
}
```

Per app: `name`, `client_id_hint` (first 8 characters of the client id, never the secret), `default`, `oauth2_users`
(usernames with a stored OAuth2 token: names only, no expiry), `oauth1` and `bearer` (presence booleans),
`bearer_source` (`env` or `store`; omitted when `bearer` is `false`; `env` appears only on a registered app, so an
`XURL_BEARER_TOKEN` with no app in the store is not listed at all, though read verbs still use it), `redirect_uri` with
`redirect_uri_source` (`env-var` / `app-config` / `built-in-default`) and `redirect_uri_stored` when the env var
overrides a stored value, and `oauth2_unnamed` only when a `/2/users/me`-failed salvage token exists. No secret or token
value is ever rendered.

It does not hit the X API. An empty store answers `{"status":"ok","apps":[]}`. `xr auth apps list --output json` returns
the same shape.

```bash
xr auth status --output json | jaq -r '.apps[] | select(.default) | .name'        # active app
xr auth status --output json | jaq -r '.apps[] | "\(.name): \(.oauth2_users | join(","))"'
xr auth status --output json | jaq -e '.apps[] | select(.default) | .oauth2_users | length > 0' >/dev/null \
  && echo "a user token is staged on the default app"
```

Token expiry is not reported; `xr` refreshes an expired OAuth2 access token transparently on the next call when a
refresh token is stored, and answers `reason: "auth-required"` (exit `77`) when it cannot. An HTTP 401 from the API is
the same `auth-required` at `77`, without a `next_step`: the credential exists but X rejected it, so the fix is a scope
or a re-enrollment, not a store repair.

## When a verb exits 77

Exit `77` is `auth-required` (or `token-store`): nothing usable was staged for the call. The envelope says what to do
next, so read `next_step` rather than guessing:

```bash
xr auth status --output json                 # {"status":"ok","apps":[...]}; each entry carries client_id_hint and bearer
xr whoami --output json 2>&1 >/dev/null      # the failure itself, carrying next_step
```

Branch on `next_step.action`:

- `register-app`: nothing is registered. `next_step.template` is `xr auth apps add <name> --client-id <client-id>
  --client-secret <client-secret>`; ask the user for the values, never invent them.
- `sign-in`: the app has client credentials but no token. `next_step.command` is the headless two-step form (`xr auth
  oauth2 --no-browser --step 1`); run it verbatim, then step 2.
- `select-app`: another registered app is the one to use. `next_step.command` names it with `--app`; run verbatim.
- `inspect-store`: `~/.xurl` exists but could not be read. `next_step.command` is `xr auth status`, whose `message`
  names the file. Back it up, then `xr auth clear --all --force` or move it aside, and re-run the flow.

Every message-shaped auth verb (`apps add`, `apps update`, `apps remove`, `default`, `clear`, `app --bearer-token`)
answers `{"status":"ok","message":"…"}` under `--output json`; `apps add` also carries `default` (whether the new app
became the default) and a `sign-in` `next_step` so the following command is already spelled out. The full recipe with a
script skeleton is in [output-envelope.md § Exit 77 recipe](output-envelope.md#exit-77-recipe).

## OAuth2 PKCE browser flow (the default for humans)

```bash
xr auth oauth2
```

`xr` opens the browser, the user grants scopes, the loopback callback finalizes the exchange, the access and refresh
tokens land in `~/.xurl`. Done.

If multiple apps are registered, `xr` uses the default app unless `--app <name>` is passed. Set the default with `xr
auth default <name>` (or run `xr auth default` for an interactive picker).

Optional positional `<USERNAME>`: skips the `/2/users/me` lookup at the end (saves one API call when the user already
knows which account they're authenticating).

## OAuth2 PKCE headless flow (the default for agents)

When stdout is not a TTY (piped runs, CI), `--no-browser` auto-engages. To use it explicitly:

```bash
# Step 1: emit the auth URL. Under --output json the URL is the `auth_url` field.
xr auth oauth2 --no-browser --step 1 --output json

# User opens that URL in any browser, completes the grant, copy-pastes the redirect URL back.

# Step 2: exchange. Use `-` to read the redirect URL from stdin (recommended on shared machines).
echo "<paste redirect URL>" | xr auth oauth2 --no-browser --step 2 --auth-url - --output json
```

The two-step shape is the only safe path for agents driving a remote machine. Never `--auth-url` on the command line on
a multi-user host, because the URL contains the authorization code, which shell history will store.

Override the default with `XURL_NO_BROWSER=1` on hosts that should never attempt to open a browser.

Step 1 against an app with no client id answers `reason: "client-credentials-missing"`, exit `2`, with a `select-app`
`next_step` when another registered app has credentials, or a `register-app` `next_step` (a `template`, values from
the user) when none does.

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

For read-only v2 endpoints and search. Cannot post, like, follow, etc. A write verb against an app whose only
credential is a Bearer answers `reason: "auth-method-mismatch"`, exit `2`, with `available_in_app: ["app"]` and the
schemes the endpoint accepts in `supported`. Forcing `--auth app` on a read when no bearer is staged answers `reason:
"auth-required"`, exit `77`, with no `next_step`: stage one with `xr auth app --bearer-token` or drop the flag.

## Multi-app management

```bash
# Register an app. Answers status: "ok" with a sign-in next_step.
xr auth apps add my-app --client-id "$ID" --client-secret "$SECRET" --output json

# List, update, remove.
xr auth apps list --output json | jaq -r '.apps[].name'
xr auth apps update my-app --client-secret "$NEW_SECRET" --output json
xr auth apps remove my-app --force --output json      # --force skips the prompt; required without a TTY

# Set default app for new shells.
xr auth default my-app             # by name
xr auth default my-app alice       # app + default user together (two documents under --output json)
xr auth default                    # interactive picker

# Per-request override (no default change).
xr --app my-app /2/users/me --output json
```

Each app carries its own per-user OAuth2 tokens and its own OAuth1 keys.

The OAuth2 redirect URI is per-app and configurable:

```bash
xr auth apps redirect-uri get my-app --output json              # effective value, its source, and the stored value
xr auth apps redirect-uri set my-app "<URI>" --output json      # must match the app's registered URI in X's developer portal
xr auth apps redirect-uri set my-app ""                         # clear the stored value
```

## Clearing tokens

`xr auth clear` needs a selector; without one it answers `reason: "validation"`, exit `1`. Destructive, so it prompts on
a TTY; pass `--force` when running unattended.

```bash
xr auth clear --all --force --output json                       # every credential on the active app
xr auth clear --bearer --force --output json                    # only the bearer
xr auth clear --oauth2-username alice --force --output json     # one OAuth2 user
xr auth clear --oauth1 --force --output json                    # only the OAuth1 token
xr auth clear --all --force --app my-app --output json          # a specific app
```

Use this before re-running a flow when `xr auth status` shows an entry you no longer want.

## Token store

YAML at `~/.xurl` (override the path with `XURL_TOKEN_STORE`). Multi-app, with transparent format migration on every
load. Every write is atomic, created `0600`, and serialized across concurrent `xr` processes by an OS file lock at
`~/.xurl.lock`, so two agents refreshing a token at once cannot truncate the store or drop a rotated refresh token.
Don't hand-edit it; use `xr auth ...` commands. If the file is corrupt, `xr auth status` answers `reason:
"token-store"` (exit `77`) naming the path; back it up, move it aside, and run a fresh `xr auth apps add` + `xr auth
oauth2`.

## Where to find scope and grant details

`xr` does not enumerate the X-API-side scope catalog. Scopes change with OAuth2 client configuration in X's developer
portal, and the authoritative list lives at
<https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code.md> (append `.md` for agent-friendly
markdown).

When a verb returns `reason: "auth-required"` after a successful auth flow, the most likely cause is a missing scope in
the OAuth2 app configuration, not a `xr` bug. Have the user grant the additional scope in the developer portal, re-run
the OAuth2 flow, and re-try. When X refuses the app itself (a 403 whose body names `client-not-enrolled` or
`client-forbidden`), the envelope is `reason: "forbidden"` with an `enroll-app` `next_step` whose `docs` URL is the
enrollment recipe; a bare `forbidden` (no `next_step`) is an ordinary permission refusal, read `message`.

`xr auth oauth2` on `xr 4.x` requests the scopes the `broadcasts` verbs need (the release notes name
`broadcast.read` and `broadcast.write`; the vendored X API spec agrees). A token enrolled before those scopes were
requested does not carry them: `xr broadcasts moderators …` answers `auth-required` (or a bare `forbidden`) until the
user re-runs `xr auth oauth2` for that app, after the app's developer-portal configuration allows the scopes.
