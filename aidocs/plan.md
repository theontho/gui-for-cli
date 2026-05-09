# GUI for CLI — Execution Plan (Expanded)

## Program intent
Build a production-ready, data-driven GUI shell for CLI tools across macOS, iOS, and WebUI, while
keeping the Swift package and command-line workflows as the source of truth.

## Current baseline
- Shared domain logic exists in `GUIForCLICore`.
- CLI surface (`precheck`, `config`, `run`, bundle helpers) is established.
- App and WebUI rendering pipelines are functional with localization and setup models.
- Validation hooks exist locally and in CI (`make lint`, `make test`, `make build-cli`, workflows).

## Delivery tracks

### 1) Product capability track
1. Harden bundle authoring ergonomics
   - Improve manifest diagnostics with clearer field-level failures.
   - Add stricter validation profiles for release bundles vs local development bundles.
2. Expand setup orchestration
   - Increase parity between setup planning, dry-run output, and execution behavior.
   - Strengthen environment interpolation guardrails for script/setup steps.
3. Improve runtime UX
   - Refine disabled-state messaging and action prechecks.
   - Standardize high-signal error and recovery paths for non-happy-path commands.

### 2) Infrastructure and quality track
1. Cross-platform reliability
   - Keep script/bootstrap tests platform-aware so supported behavior is asserted per OS.
   - Ensure tests verify portability contracts instead of POSIX-only assumptions.
2. CI fidelity
   - Keep `scripts/ci-local.py` and workflow jobs aligned to prevent local-vs-CI drift.
   - Continue pinning GitHub Actions and dependencies with controlled upgrade cadence.
3. Validation depth
   - Expand targeted tests around bundle workspace sync, setup scripts, and config bootstrap.
   - Strengthen smoke-style checks for localization and accessibility paths.

### 3) App/WebUI parity track
1. Rendering model parity
   - Keep page/section/control semantics and conditional visibility behavior consistent.
2. Setup experience parity
   - Keep setup command presentation and status semantics consistent between surfaces.
3. Localization parity
   - Ensure missing-key fallback and language selection behavior match across clients.

## Near-term execution order
1. Stabilize cross-platform infra/test behavior.
2. Tighten setup/config bootstrap consistency in core and CLI.
3. Close app/WebUI parity gaps for setup and conditional controls.
4. Expand release-readiness checks (a11y/localization + bundle validation strictness).

## Definition of done for this phase
- No known platform-specific false failures in core setup/bootstrap tests.
- CI workflows reflect the same checks developers run locally.
- Core setup/config behaviors are deterministic across CLI, app, and WebUI surfaces.
