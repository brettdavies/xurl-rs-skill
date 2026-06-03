# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this skill bundle (for example, a script in `scripts/` or a template under
`templates/` that could execute unintended code on a user's machine at install time), please report it via GitHub's
private security advisories rather than filing a public issue:

[Open a private security advisory](https://github.com/brettdavies/xurl-rs-skill/security/advisories/new)

## Disclosure Window

We aim to acknowledge reports within 5 business days and to publish a fix or mitigation within **90 days** of the
initial report. Coordinated disclosure is preferred; we will work with reporters to align on a public-disclosure date
that protects users while crediting the finder.

## Scope

In scope:

- Shell scripts under `scripts/` and `scripts/checks/`.
- Templates under `templates/` (which users may copy into their own projects).
- Governance files (`CODEOWNERS`, CI workflows) where misconfiguration could allow unreviewed code to ship.

Out of scope:

- Vulnerabilities in [`xurl-rs`](https://github.com/brettdavies/xurl-rs) itself — file those against that repository.
- Best-practice debates about the skill's guidance; open a regular issue or PR for those.

## Supported Versions

Only the latest tagged release receives security fixes. Older tags are immutable historical records.
