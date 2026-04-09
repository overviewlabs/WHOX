# WHOX Changelog

## v0.1.1 - 2026-04-09

- Hardened installer for idempotent update-in-place behavior on existing WHOX installs.
- Added snapshot-first configuration flow so installs align with the working WHOX profile.
- Added prerequisite bootstrap before major install stages.
- Improved Firecrawl startup reliability and health-check diagnostics.
- Added strict post-install readiness gates (CLI, gateway service, Firecrawl health).
- Added sanitized runtime/firecrawl snapshot templates for reproducible functional setup.

## v0.1.0 - 2026-04-08

- Initial WHOX functional snapshot release.
