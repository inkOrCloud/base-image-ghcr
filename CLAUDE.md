# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This repo builds Vast.ai Docker images and provisioning assets for GPU-oriented templates. The core idea is a shared base image that provides Vast-specific startup infrastructure, then three image families on top:

- `derivatives/` — images built from `vastai/base-image` or `vastai/pytorch`
- `external/` — upstream images wrapped with Vast infrastructure
- `provisioning_scripts/` — boot-time setup scripts for stock base-image templates

## High-level architecture

- `ROOT/` is a filesystem overlay copied into images as-is.
  - `ROOT/etc/vast_boot.d/` contains numbered boot scripts that run in order during startup.
  - `ROOT/opt/supervisor-scripts/` contains wrapper scripts for supervised services.
  - `ROOT/provisioning.yaml` is the declarative provisioning manifest used at boot.
- Supervisor is the process manager for long-running apps; each service typically needs both a shell wrapper and a `supervisord` config.
- `PORTAL_CONFIG` controls which apps appear in the Instance Portal and which ports are proxied.
- `WORKSPACE`/`DATA_DIRECTORY` map to the persistent workspace; `opt/workspace-internal/` is copied there on first boot.
- Image types differ in how they are assembled:
  - Derivatives extend prebuilt Vast images and should bake dependencies into the image.
  - External images start from large upstream images and graft on Vast infrastructure.
  - Provisioning scripts are for quick boot-time setup, but should be converted to derivative images once validated.
- PyTorch images have a dedicated build matrix and special handling for CUDA/Python version combinations.

## Common commands

Build the base image variants from source:

```bash
./build.sh --list
./build.sh --filter cuda-12.8 --dry-run
./build.sh --filter cuda-12.8
```

Build a single Docker image directly:

```bash
docker buildx build --progress=plain -f Dockerfile .
```

Build a specific derivative image:

```bash
cd derivatives/pytorch
docker buildx build --progress=plain -f Dockerfile .
```

Build the PyTorch image matrix:

```bash
cd derivatives/pytorch
./build-many.sh
./build-many-24.04.sh
```

Run a provisioning script locally on an instance/template context by setting `PROVISIONING_SCRIPT` to its raw URL at boot; the script itself should be executable Bash with `set -euo pipefail`.

## Testing and verification

There does not appear to be a single repo-wide test runner. The usual verification flow is:

- `docker buildx build ...` for the image you changed
- `./build.sh --dry-run` or `--list` when adjusting build matrices
- Inspect the relevant boot or supervisor scripts under `ROOT/` when changing startup behavior

For single files, run the narrowest build that exercises that image family rather than a full repo build.

## Conventions worth preserving

- Use `set -euo pipefail` in shell scripts.
- Activate the shared venv with `. /venv/main/bin/activate`.
- Use `uv pip install` instead of plain `pip` in image build steps.
- Put app files under `/opt/workspace-internal/` when they should sync into the workspace on first boot.
- Supervisor scripts should source utilities from `/opt/supervisor-scripts/utils/` in the established order.
- For derivative Dockerfiles, keep the standard label block, `COPY ./ROOT /`, PyTorch version checks, and `env-hash > /.env_hash` where applicable.
- For external images, preserve the multi-stage pattern and the `convert-non-vast-image.sh` grafting step.

## Where to look first

- `README.md` for the overall platform model and startup behavior
- `CONTRIBUTING.md` for repo structure and image-creation patterns
- `.github/AGENTS.md` for CI workflow conventions
- `ROOT/opt/supervisor-scripts/README.md` for wrapper-script expectations
- `derivatives/README.md` for the derivative-image layout
