# AGENTS.md

## Repository summary

This repository currently implements and ships a standalone VPS workflow.

Present in this snapshot:

- `install_standalone.sh`
- `core/standalone_daemon.sh`
- `core/mod_google_curl_imp.sh`
- `core/mod_trust_curl_imp.sh`
- `core/updater.sh`
- `core/uninstall.sh`
- `data/`
- `scripts/`
- `telemetry/worker.js`

Not present in this snapshot:

- A deployable `master/` directory
- A repository-local typecheck/lint/test/build toolchain configuration

## Documentation decisions

- 2026-04-15: `README.md` was rewritten to match the actual repository contents instead of the previously described distributed architecture.
- 2026-04-15: `telemetry/worker.js` is documented as standalone because the install/runtime scripts do not call its endpoints.

## Verification commands

Current repository snapshot has no root-level commands configured for:

- Typecheck
- Lint
- Tests
- Build

When modifying documentation only, verify in strict order by confirming whether repository configuration exists for each stage before attempting execution.