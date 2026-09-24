# Template: OAuth2 first-time setup

Copy this template into your working scratchpad, fill the placeholders, and execute the steps in order. Pick branch A
(browser, desktop) OR branch B (headless, SSH / container / CI); they're mutually exclusive.

## Pre-flight

```bash
xr version                                  # confirm xr is installed
xr auth status --output json                # {"status":"ok","apps":[...]}: what's already staged
xr auth apps list --output json | jaq -r '.apps[].name'     # which apps are registered
```

Both `auth status` and `auth apps list` wrap the array: read entries through `.apps[]`, never as a bare top-level array.
An empty store answers `"apps": []`.

If the user has no apps registered (`"apps": []`), register one before authenticating:

```bash
xr auth apps add <APP_NAME> \
  --client-id "<CLIENT_ID>" \
  --client-secret "<CLIENT_SECRET>" \
  --output json
```

The answer is a success envelope that already names the next command (the Branch B step 1 below, runnable verbatim):

```json
{
  "status": "ok",
  "message": "App \"<APP_NAME>\" registered.",
  "default": true,
  "next_step": { "action": "sign-in", "command": "xr auth oauth2 --no-browser --step 1" }
}
```

A read verb run before any of this exits `77` with `reason: "auth-required"` and a `next_step` whose `action` is
`register-app` and whose `template` is the `apps add` invocation above with angle-bracket placeholders. Ask the user
for the values; never invent a client id or secret.

> **Never paste `--client-secret` inline on a shared host.** Pull it from a secrets manager:
> `--client-secret "$(op read op://<vault>/<item>/client_secret)"`

Set this app as default (so subsequent commands use it without `--app`):

```bash
xr auth default <APP_NAME>
```

## Branch A: browser flow (desktop with a GUI)

```bash
xr auth oauth2
```

`xr` opens the browser; the user grants the scopes the app's developer-portal configuration requests; the loopback
callback finalizes the exchange.

Optional shortcut: append the X username to skip the `/2/users/me` lookup at the end:

```bash
xr auth oauth2 <X_USERNAME>
```

## Branch B: headless flow (SSH, container, CI)

Two steps. Step 1 emits the auth URL. The user opens it in any browser, completes the grant, and pastes the redirect URL
back. Step 2 exchanges the code.

```bash
# Step 1.
xr auth oauth2 --no-browser --step 1 --output json
```

Under `--output text` this prints the URL to open. Under `--output json` it answers `{"status":"ok","auth_url":"…",
"instructions":"…"}`; read `.auth_url`. Against an app with no client id it answers `reason:
"client-credentials-missing"`, exit `2`, with a `select-app` `next_step` when another registered app does have one and
a `register-app` `next_step` (a `template` to fill with the user's values) when none does.

User opens the URL in any browser, completes the grant, and captures the redirect URL from the address bar.

```bash
# Step 2. Read the redirect URL from stdin (avoids shell history on a shared host).
echo "<paste-redirect-url>" | xr auth oauth2 --no-browser --step 2 --auth-url -
```

Or pass it inline (only safe on a single-user machine):

```bash
xr auth oauth2 --no-browser --step 2 --auth-url "<REDIRECT_URL>"
```

## Verify

```bash
xr auth status --output json
xr auth status --output json | jaq -e '.apps[] | select(.name == "<APP_NAME>") | .oauth2_users | index("<X_USERNAME>")'
```

Expect, in the `.apps[]` entry for `<APP_NAME>`:

- `oauth2_users` containing the username the flow resolved (or the one passed positionally).
- `default: true` if it is the app subsequent commands should use.

`auth status` reports presence only: no token values, no expiry. `xr` refreshes an expired access token transparently
on the next call.

Round-trip with a real read call to confirm scopes:

```bash
xr whoami --output json
```

If `whoami` exits `0` and prints the API document (`{"data":{"id":"…","username":"…","name":"…"}}`; API-backed
successes carry no `status` key), you're authenticated and the basic user-read scope is granted. If it exits `77`, the
envelope on stderr carries a `next_step` naming the fix; see the troubleshooting table.

## Troubleshooting

| Symptom                                                              | Likely cause                                  | Fix                                                                                 |
| -------------------------------------------------------------------- | --------------------------------------------- | ----------------------------------------------------------------------------------- |
| Exit `77`, `next_step.action: "register-app"`                        | No app registered                             | Run the Pre-flight `apps add` with real values from the user                        |
| Exit `77`, `next_step.action: "sign-in"`                             | App registered, no token                      | Run `next_step.command` verbatim (Branch B step 1), then step 2                     |
| Exit `77`, `next_step.action: "select-app"`                          | The credentials live on another app           | Run `next_step.command` verbatim; it names the app with `--app`                     |
| Exit `77`, `next_step.action: "inspect-store"`                       | `~/.xurl` exists but could not be read        | `xr auth status` names the file; back it up, move it aside, re-run                  |
| `reason: "auth-method-mismatch"`, exit `2`                           | Only a Bearer is staged, or `--auth` is wrong | Read `supported`; run the OAuth2 flow or drop the `--auth` flag                     |
| `reason: "client-credentials-missing"` on step 1                     | Target app has no client id                   | Follow its `next_step`, or `apps update <APP_NAME> --client-id … --client-secret …` |
| Browser opens to a redirect-uri mismatch error                       | Registered URI differs from `xr`'s            | `xr auth apps redirect-uri set <APP_NAME> <URI>` to match the portal                |
| `reason: "auth-required"` after a successful flow, no `next_step`    | A scope the verb needs wasn't requested       | Re-grant the missing scope in the developer portal, re-run flow                     |
| `reason: "forbidden"`, `next_step.action: "enroll-app"`              | X refused the app (403 naming enrollment)     | Open `next_step.docs`; the fix is in the developer portal                           |
| `reason: "forbidden"`, no `next_step`                                | The token lacks a scope, or the tier the path | Read `message`; grant the scope in the portal and re-run the flow, or change tier   |
| `broadcasts moderators …` exits `77` on a token that works elsewhere | Token predates the `broadcast.*` scopes       | Allow them in the portal, then re-run Branch A or B for that app                    |
| `reason: "token-store"` from `auth status`                           | `~/.xurl` is corrupt or unreadable            | Back up `~/.xurl`, move it aside, re-run Pre-flight                                 |
| Browser never opens (Branch A on a headless host)                    | Use Branch B                                  | `xr auth oauth2 --no-browser --step 1 / 2`                                          |
| Step 2 fails with `invalid_grant`                                    | Code expired (typically ~60s after grant)     | Re-run Step 1, complete Step 2 promptly                                             |

## Multi-user on the same app

To register multiple X accounts under one app:

```bash
xr auth oauth2 <USERNAME_A>             # auth user A
xr auth oauth2 <USERNAME_B>             # auth user B
xr auth status --output json | jaq -r '.apps[] | select(.name == "<APP>") | .oauth2_users[]'   # confirm both
xr auth default <APP> <USERNAME_A>      # set the default app + user for new shells
xr --username <USERNAME_B> whoami       # one-off override (-u for short)
```

## Adjacent: app-only Bearer (no user flow needed)

For read-only v2 + search, you can stage a Bearer token without OAuth2:

```bash
xr auth app --bearer-token "$XURL_BEARER_TOKEN"
xr search "rustlang" --auth app --output json
```

This does NOT enable posting, liking, following, DMs, or any other user-scoped verb.
