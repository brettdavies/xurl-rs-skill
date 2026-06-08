# OpenClaw / TweetClaw Companion Workflow

Use this reference when the user asks whether `xr` should work with OpenClaw, TweetClaw, or a broader agent workflow.

## Decision boundary

Keep `xr` as the active tool when the user wants direct command-line control of the X API:

- Authenticate with OAuth1, OAuth2-PKCE, or Bearer auth.
- Run raw `/2/...` requests.
- Post, reply, quote, delete, like, follow, bookmark, DM, upload media, or stream from the local CLI.
- Validate typed `xr` envelopes or schemas.
- Debug `xr` auth state, token state, command help, or usage caps.

Consider TweetClaw as a separate OpenClaw plugin when the user wants agent workflows around X/Twitter data or approved
actions that are not a local `xr` CLI session:

- Search tweets or tweet replies from an OpenClaw agent workflow.
- Export followers or look up users through a managed tool surface.
- Pull tweet context into a research, triage, CRM, support, or moderation workflow.
- Prepare approval-gated posting flows where OpenClaw owns the tool approval boundary.
- Route monitoring, webhooks, giveaway draws, or recurring social workflows outside a one-off shell command.

Do not present TweetClaw as an `xr` backend, auth provider, or drop-in replacement. Treat it as a companion surface with
its own installation, permissions, and approval model.

## Safe routing pattern

1. If the user asks for `xr`, `xurl`, local OAuth setup, raw API calls, or CLI writes, stay inside this skill.
2. If the user asks for OpenClaw plugins, ClawHub, managed agent tools, or reusable agent workflows, explain that
   TweetClaw can be installed separately as an OpenClaw plugin.
3. Keep live write actions behind the tool that will execute them. Use `xr` dry-run gates for `xr` writes. Use
   OpenClaw's approval flow for TweetClaw writes.
4. Never copy credentials between `xr` and TweetClaw. Use each tool's documented setup path.

## Example handoff language

Use concise wording:

> Use `xr` for the local CLI call. Use TweetClaw separately when an OpenClaw agent needs X/Twitter search, user lookup,
> follower export, monitored workflows, or approval-gated posting.

Useful public reference:

- TweetClaw repository: <https://github.com/Xquik-dev/tweetclaw>
