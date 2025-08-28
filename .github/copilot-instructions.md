# Copilot Instructions

Minimal guidance for AI assistants. For comprehensive details (targets, stages, style, tooling) see `CLAUDE.md` and the `README.md`.

## Build
- Unified script: `./build.sh <full|r-ci>`
- Cross-build amd64: `./build.sh --amd64 <target>` (auto artifact output unless `--output load`)
- Artifact outputs: `--output oci` (directory) or `--output tar` (docker loadable)
- Debug R packages: `--debug`
- Disable cache: `--no-cache`
- Parallel R build jobs: env `R_BUILD_JOBS=N`

## Publish
- Multi-arch push: `./push-to-ghcr.sh -a` (creates & pushes manifest list)
- Single-arch push: build (load) then tag & push manually or via `push-to-ghCR.sh` (host arch).

## Targets
- `full`: complete dev environment (Neovim, LaTeX, Pandoc, R, Python, VS Code server)
- `r-ci`: slim R-focused CI image (R + selected packages + JAGS)

## Conventions
- Local images include arch suffix (e.g. `full-amd64`).
- Use `--output` for daemonless or cross builds to avoid flaky `--load` streams.
- Prefer small, focused changes; avoid reintroducing legacy scripts.

## When Editing
1. Keep `build.sh` single-purpose (no multi-loop orchestration).
2. Don't add new dependencies without clear value.
3. Update `README.md` if user-facing behavior changes.
4. Reflect any assistant-facing process changes back into `CLAUDE.md`.

Refer to `CLAUDE.md` for deep architecture notes and style guidelines.
