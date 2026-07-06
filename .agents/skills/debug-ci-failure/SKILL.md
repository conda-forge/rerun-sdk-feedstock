---
name: debug-ci-failure
description: Diagnose a failing CI build on the rerun-sdk conda-forge feedstock, typically an autotick-bot version-bump PR. Use when asked to "debug the CI failure", "why is the build failing", "diagnose PR #N", or when a version bump broke the conda build. Finds the real error across GitHub Actions and Azure logs, traces it to the upstream rerun dependency change, and proposes the recipe/meta.yaml fix.
---

# Debugging rerun-sdk-feedstock CI failures

This is a conda-forge feedstock that builds `rerun-sdk` from the Rust+Python
source at https://github.com/rerun-io/rerun. Almost every failure is a
bot-opened **version-bump PR** (branch like `0.34.0_h52a998`) where the new
upstream release added or changed a dependency that needs new conda build
config. The Rust source and `build.sh`/`bld.bat` rarely change; the fix is
almost always in `recipe/meta.yaml` (or `recipe/conda_build_config.yaml`).

## Workflow

### 1. Find the PR and see which platforms fail

```bash
gh pr list --repo conda-forge/rerun-sdk-feedstock
gh pr view <N> --repo conda-forge/rerun-sdk-feedstock \
  --json title,headRefName,statusCheckRollup,files
```

Note the pattern of failures — it tells you where to look and whether there's
one root cause:
- **All platforms fail** → one common cause (a build tool, a solve error, a
  toolchain bump). Read one log.
- **Some platforms pass, others fail** → still usually ONE upstream cause with
  **platform-specific symptoms**. macOS often passes because its backends
  (IOKit, system frameworks) are already present, while linux/windows need
  explicit deps. Don't assume different failures = different causes; check.

The branch name encodes the new upstream commit (`<version>_h<short-sha>`).

### 2. Get the REAL error (two log systems)

**GitHub Actions** hosts `linux_*` (and appears in `statusCheckRollup` as
`CheckRun` with a `github.com/.../actions/runs/.../job/<jobId>` URL):

```bash
gh run view --repo conda-forge/rerun-sdk-feedstock --job <jobId> --log > full.log
```

**Azure Pipelines** hosts `win_*` and `osx_*` (check `detailsUrl` points to
`dev.azure.com`). `gh` can't read these — use the REST API. Extract `buildId`
and the project GUID from the `detailsUrl`, then:

```bash
# 1. timeline → find failed records and their log ids
curl -s "https://dev.azure.com/conda-forge/feedstock-builds/_apis/build/builds/<buildId>/timeline?api-version=6.0" \
  | python3 -c "import json,sys
for r in json.load(sys.stdin)['records']:
    if r.get('result')=='failed' and r.get('log'): print(r['log']['id'], r.get('name'))"

# 2. fetch the log for the failing 'Run Windows build' / build record
curl -s "https://dev.azure.com/conda-forge/<projectGuid>/_apis/build/builds/<buildId>/logs/<logId>?api-version=6.0" > win.log
```

**Filter the noise.** These logs are huge and mostly post-failure artifact
upload. Grep for the actual error and exclude packaging chatter:

```bash
grep -niE "error(\[|:)|panicked|failed to run custom build|could not compile|returned non-zero exit|OverLinkingError|not found in packages" full.log \
  | grep -viE "adding:|Uploaded bytes|_build_env|/doc/|\.html|rerun-if-env"
```

Signals that mark the true failure:
- `error: failed to run custom build command for \`<crate>\`` + `panicked` — a
  Rust build script (usually a `-sys` crate) needs a system tool/lib.
- `The <tool> command could not be found` (e.g. pkg-config).
- `OverLinkingError` / `... .dll not found in packages, sysroot(s) nor the
  missing_dso_allowlist` — a Windows link-check on a system DLL.
- `returned non-zero exit status 101` — generic cargo failure; the real cause
  is just above it.
- conda solver errors — a version pin in meta.yaml conflicts with new deps.

### 3. Trace it to the upstream dependency change

Confirm the offending crate/dep is NEW in this release by diffing `Cargo.lock`
between the previously-shipped tag and the new one:

```bash
# new version (from PR branch name / meta.yaml)
https://raw.githubusercontent.com/rerun-io/rerun/<new-version>/Cargo.lock
# previous version (from git log / prior meta.yaml)
https://raw.githubusercontent.com/rerun-io/rerun/<old-version>/Cargo.lock
```

Search both for the crate named in the error and for what pulls it in. A crate
present in the new lock but absent in the old confirms the version bump
introduced it. Hardware/device crates are frequent offenders and explain
per-platform splits (e.g. a gamepad crate → libudev on linux, WinRT DLL on
windows, IOKit on macOS-which-passes).

### 4. Confirm the conda-forge package exists before proposing it

```bash
curl -s "https://api.anaconda.org/package/conda-forge/<pkg>" \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('latest_version'),d.get('summary'))"
# check it covers the failing subdirs (linux-64, linux-aarch64, ...)
curl -s "https://api.anaconda.org/package/conda-forge/<pkg>/files" \
  | python3 -c "import json,sys;print(sorted({f['attrs']['subdir'] for f in json.load(sys.stdin)}))"
```

## Common fixes (all in `recipe/meta.yaml`, always platform-gated)

Gate every addition with a conda selector so platforms that already pass stay
untouched, and add a short comment naming the upstream dep that caused it.

- **New build-time tool** (pkg-config, cmake, etc.) → `requirements: build:`
  ```yaml
  - pkg-config  # [linux]
  ```
- **New system library to link/compile against** → `requirements: host:`
  (conda-forge lib packages usually carry run_exports, so the runtime dep is
  added automatically — no `run:` entry needed).
  ```yaml
  - libudev  # [linux]
  ```
- **Windows overlinking on an always-present system DLL** (`api-ms-win-*`, and
  similar) → top-level `build: missing_dso_whitelist:`
  ```yaml
  build:
    missing_dso_whitelist:
      - '*/api-ms-win-core-winrt-l1-1-0.dll'  # [win]
  ```
- **Rust toolchain too old/new for a new crate** → bump `rust_compiler_version`
  in `recipe/conda_build_config.yaml`.
- **Solver conflict from a version pin** → relax/adjust the pin in `run:`/`host:`.

## Notes

- On a version-bump PR keep `build: number: 0`. Only bump the build number when
  re-releasing config fixes against an already-published version.
- Prefer an additive conda-config fix over patching upstream sources; if
  upstream exposes a cargo feature to drop the offending dependency that's a
  cleaner alternative, but the feedstock uses fixed feature sets
  (`release_full`, `pypi`), so features usually can't be trimmed here.
- Theory-verified fixes still need a real CI run. Push to the bot's branch and
  let it rebuild to confirm all platform families go green.
