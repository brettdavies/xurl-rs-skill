# Template — OAuth2 first-time setup

Copy this template into your working scratchpad, fill the placeholders, and execute the steps in order. Pick branch A
(browser, desktop) OR branch B (headless, SSH / container / CI) — they're mutually exclusive.

## Pre-flight

```bash
xr version                                  # confirm xr is installed
xr auth status --output json                # see what's already staged
xr auth apps list --output json             # see which apps are registered
```

If the user has no apps registered, register one before authenticating:

```bash
xr auth apps add <APP_NAME> \
  --client-id "<CLIENT_ID>" \
  --client-secret "<CLIENT_SECRET>"
```

> **Never paste `--client-secret` inline on a shared host.** Pull it from a secrets manager:
> `--client-secret "$(op read op://<vault>/<item>/client_secret)"`

Set this app as default (so subsequent commands use it without `--app`):

```bash
xr auth default <APP_NAME>
```

## Branch A — browser flow (desktop with a GUI)

```bash
xr auth oauth2
```

`xr` opens the browser; the user grants the scopes the app's developer-portal configuration requests; the loopback
callback finalizes the exchange.

Optional shortcut: append the X username to skip the `/2/users/me` lookup at the end:

```bash
xr auth oauth2 <X_USERNAME>
```

## Branch B — headless flow (SSH, container, CI)

Two steps. Step 1 emits the auth URL. The user opens it in any browser, completes the grant, and pastes the redirect URL
back. Step 2 exchanges the code.

```bash
# Step 1.
xr auth oauth2 --no-browser --step 1
```

Output (under `--output text`) prints the URL to open. Under `--output json`, the URL appears as a structured field.

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
```

Expect:

- An entry for `<APP_NAME>` with an `oauth2` block.
- `expires_at` in the future.
- `refresh_token` present (so `xr` can rotate transparently).

Round-trip with a real read call to confirm scopes:

```bash
xr whoami --output json
```

If `whoami` returns a `status: "ok"` envelope, you're authenticated and the basic `users.read` scope is granted.

## Troubleshooting

| Symptom                                           | Likely cause                              | Fix                                                                |
| ------------------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------ |
| Browser opens to a redirect-uri mismatch error    | Registered URI differs from `xr`'s        | `xr auth apps redirect-uri <APP_NAME> --set <URI>` to match portal |
| `reason: "auth-required"` after a successful flow | A scope the verb needs wasn't requested   | Re-grant the missing scope in the developer portal, re-run flow    |
| `reason: "token-store"`                           | `~/.xurl` is corrupt or unreadable        | Back up `~/.xurl`, `xr auth clear`, re-run                         |
| Browser never opens (Branch A on a headless host) | Use Branch B                              | `xr auth oauth2 --no-browser --step 1 / 2`                         |
| Step 2 fails with `invalid_grant`                 | Code expired (typically ~60s after grant) | Re-run Step 1, complete Step 2 promptly                            |

## Multi-user on the same app

To register multiple X accounts under one app:

```bash
xr auth oauth2 <USERNAME_A>             # auth user A
xr auth oauth2 <USERNAME_B>             # auth user B
xr auth status --output json            # confirm both
xr auth default --app <APP> <USERNAME_A> # set the default user for new shells
xr -u <USERNAME_B> whoami               # one-off override
```

## Adjacent: app-only Bearer (no user flow needed)

For read-only v2 + search, you can stage a Bearer token without OAuth2:

```bash
xr auth app --bearer-token "$XURL_BEARER_TOKEN"
xr search "rustlang" --auth app --output json
```

This does NOT enable posting, liking, following, DMs, or any other user-scoped verb.
