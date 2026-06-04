# X API essentials

This file is about the **X API itself**: where the authoritative docs live, what the API surface looks like, the auth
model, tier and rate-limit conventions, response shape, and the categories of endpoints `xr` does not ship a shortcut
for. It is intentionally a **drift-resistant pointer** rather than a copy of the X docs — the API changes faster than
this bundle is republished.

For how to drive the API from the command line, look elsewhere in this bundle: [auth-modes.md](auth-modes.md),
[agent-flags.md](agent-flags.md), [output-envelope.md](output-envelope.md), and the four templates.

**Verified on:** 2026-06-03. Treat any concrete name, number, or path below as a hint that should be confirmed at the
official URL before you act on it.

> **Iron rule:** never invent X API endpoint paths, OAuth scopes, billing tiers, or rate-limit numbers. They change.
> See [escalation.md](escalation.md) for the full lookup order.

## Where the authoritative answers live

### Official docs — agent-friendly markdown

Every page at <https://docs.x.com/> supports markdown by appending `.md` to the URL. Use this with the agent's
`fetch-web` or `defuddle` skill to get clean markdown without MDX clutter.

High-value entry points:

- <https://docs.x.com/llms.txt> — the full docs index, agent-ready.
- <https://docs.x.com/x-api/introduction.md> — X API v2 entry point.
- <https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code.md> — OAuth2 scopes catalog.
- <https://docs.x.com/fundamentals/rate-limits.md> — rate-limit conventions.
- <https://docs.x.com/x-api/getting-started/about-x-api.md> — tier overview.
- <https://developer.x.com/en/portal/products> — current pricing and tier configuration.

### Companion skill — `x-api`

If the user has the separate `x-api` reference skill installed at `~/.claude/skills/x-api/`, it auto-loads when an
`xr`-flavored task is in scope. The companion carries the X API OpenAPI spec, a scope catalog, billing notes, and
rate-limit tables — making it the second-best stop after the official docs above and before guessing.

## API versions

X serves two coexisting versions plus streaming endpoints:

| Version   | Status                                     | Path prefix     | Typical surface                                                        |
| --------- | ------------------------------------------ | --------------- | ---------------------------------------------------------------------- |
| v2        | Current — preferred for new work           | `/2/...`        | Posts, users, search, social graph, DMs, lists, spaces, usage          |
| v1.1      | Legacy — still required for select paths   | `/1.1/...`      | Some media endpoints, a few read paths the v2 surface has not absorbed |
| Streaming | Live filtered or sampled streams over HTTP | `/2/tweets/...` | `tweets/search/stream`, `tweets/sample/stream`; long-lived connections |

When in doubt, look up the path at <https://docs.x.com/x-api/introduction.md> — the docs split content by category, not
by API version, so a single concept (e.g., posts) may have both v1.1 and v2 surfaces.

## Authentication model

X defines three authentication contexts. Each maps to a different surface and a different set of operations.

| Context                      | Grant flow                                  | Acts as | Typical surface                          |
| ---------------------------- | ------------------------------------------- | ------- | ---------------------------------------- |
| OAuth 1.0a (User Context)    | Three-legged consumer-key / token signing   | A user  | Legacy v1.1 + a few v2 write paths       |
| OAuth 2.0 Authorization Code | PKCE; user grants scopes via consent screen | A user  | All v2 user-scoped reads and writes      |
| App-only Bearer              | Client-credentials token                    | An app  | Read-only v2 endpoints and recent-search |

### Scopes (OAuth 2.0)

OAuth 2.0 scopes are granted at two layers: at app configuration time in the developer portal (which scopes the app may
request) and at consent time by the user (which of those scopes they grant). The scope catalog is a **closed set**
defined by X — do not invent names. Scope groups historically include reads on tweets and users, writes on tweets,
follows, likes, bookmarks, DMs, mutes/blocks, and offline-access (refresh-token).

Authoritative catalog: <https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code.md>.

When an endpoint returns a missing-scope error after a successful authentication, the fix is to grant the additional
scope in the developer portal and re-run the OAuth 2.0 flow — not to retry. See [auth-modes.md](auth-modes.md) for how
to re-run via `xr`.

### Which context for which endpoint

Every endpoint page on `docs.x.com` lists its supported authentication context(s) and required scope(s). When you need
to plan an integration, read the per-endpoint doc first — context and scope requirements vary even within a single
category.

## Access tiers and billing

X gates the API behind paid access tiers. The tier you're on determines:

- The monthly tweet cap (a single project-level pool that both reads and writes draw from).
- Which endpoints are available.
- The per-window rate-limit budget.
- Access to gated features (full-archive search, large filtered streams, enterprise data products).

Tier categories historically: Free, Basic, Pro, Enterprise — but the **specific names, caps, and prices change**. Verify
before quoting any value.

Authoritative:

- <https://docs.x.com/x-api/getting-started/about-x-api.md> — tier overview.
- <https://developer.x.com/en/portal/products> — current pricing.

## Rate limits

X enforces multiple overlapping limits:

- **Per-app windows** — rolling 15-minute windows that apply across all users of an app.
- **Per-user windows** — rolling 15-minute windows that apply to a single authenticated user.
- **Project-level monthly tweet cap** — a single pool that both posts and reads draw from, sized by tier.

Conventions (stable):

- Responses include `x-rate-limit-remaining`, `x-rate-limit-limit`, and `x-rate-limit-reset` headers. `xr --verbose`
  echoes them.
- A 429 response means you've hit a limit; `Retry-After` (when present) names the seconds to wait.
- The right response is to wait until the window resets OR pivot to cached data. Tight-looping makes the limit worse.

Authoritative: <https://docs.x.com/fundamentals/rate-limits.md>.

## Response shape (v2)

Most v2 endpoints return a JSON object with up to four top-level fields:

| Field      | Meaning                                                                          |
| ---------- | -------------------------------------------------------------------------------- |
| `data`     | The primary resource(s). Single object for lookup; array for list endpoints.     |
| `includes` | Related resources joined via expansions (users, referenced tweets, media, etc.). |
| `meta`     | Pagination cursors (`next_token`, `previous_token`), result counts, ids.         |
| `errors`   | Partial errors — present alongside `data` when some entries failed to resolve.   |

Note: a top-level error response (HTTP 4xx / 5xx) is a different shape — a `{title, type, status, detail}` problem
document, not a `data + errors` envelope. The two are distinct; do not confuse them.

Per-resource shapes (Tweet, User, DM, etc.) are documented per endpoint. For the shapes `xr` types, see `xr schema
--command <name> --output json` — those mirror the API as of the bundled `xr` version.

## Pagination

X uses cursor-based pagination across every list-style endpoint:

- The first request returns up to `max_results` records and a `meta.next_token`.
- The next page is fetched by re-running with `pagination_token=<next_token>` as a query parameter.
- `meta.next_token` is omitted when there are no more pages.

X **does not support offset pagination** (`page=N`). Tools that expose `--page` for X are always translating to cursors
internally.

Authoritative: per-endpoint docs and <https://docs.x.com/x-api/posts/search/integrate/paginate.md>.

## Identifier shapes

| Identifier      | Shape                                                                      |
| --------------- | -------------------------------------------------------------------------- |
| Post (Tweet) ID | Snowflake integer (~19 digits), e.g. `1234567890123456789`.                |
| User ID         | Snowflake integer.                                                         |
| Username        | Handle without `@` in API responses; with `@` in colloquial CLI inputs.    |
| Status URL      | `https://x.com/<username>/status/<post_id>` — the trailing path is the ID. |

## Endpoint categories

`xr` ships shortcut commands for ~30 common endpoints. For everything else, drop to raw mode and consult the docs
category index:

| Category         | Docs entry                                                          |
| ---------------- | ------------------------------------------------------------------- |
| Posts            | <https://docs.x.com/x-api/posts/introduction.md>                    |
| Users            | <https://docs.x.com/x-api/users/introduction.md>                    |
| Search           | <https://docs.x.com/x-api/posts/search/introduction.md>             |
| Filtered streams | <https://docs.x.com/x-api/posts/filtered-stream/introduction.md>    |
| Sampled streams  | <https://docs.x.com/x-api/posts/sampled-stream/introduction.md>     |
| Direct Messages  | <https://docs.x.com/x-api/direct-messages/introduction.md>          |
| Lists            | <https://docs.x.com/x-api/lists/introduction.md>                    |
| Spaces           | <https://docs.x.com/x-api/spaces/introduction.md>                   |
| Bookmarks        | <https://docs.x.com/x-api/posts/bookmarks/introduction.md>          |
| Likes            | <https://docs.x.com/x-api/posts/likes/introduction.md>              |
| Media            | <https://docs.x.com/x-api/media/quickstart/media-upload-chunked.md> |
| Usage            | <https://docs.x.com/x-api/usage/get-usage.md>                       |

When `xr` does not ship a shortcut for an endpoint, the raw-mode pattern is:

```bash
xr /2/<path>                            # GET
xr -X POST /2/<path> -d '{"...": "..."}'
```

## When the X API surprises you

The X API has historically:

- Renamed scopes between OAuth 2.0 releases.
- Tightened tier gating on previously open endpoints (e.g., search).
- Adjusted rate-limit windows without changelog entries.
- Deprecated v1.1 endpoints with limited notice.

When an unexpected error comes back and `xr --verbose` shows the raw API response, **trust the API's message over any
cached expectation in this bundle**. If the discrepancy is durable (a docs page or this bundle is wrong, not just
out-of-date for one call), open an issue with the `[skill]` prefix at
<https://github.com/brettdavies/xurl-rs/issues/new/choose>.
