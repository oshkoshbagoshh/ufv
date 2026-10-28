---
sessionId: session-261022-000238-2dxs
---

# Requirements

### Overview & Goals
Prepare UFV for `/demo` to start its FastAPI application in the demo VM and provide a reliable API walkthrough.

### Scope
- Add `.junie/demo.md` and `.junie/vms/template-vm/Dockerfile` using the confirmed VM template setup.
- Launch with `uv sync` and `uv run uvicorn src.api.main:app --host 0.0.0.0`; serve on port `8000` and use `/docs` as the readiness check.
- Provide a Python >=3.13 runtime and `uv` in the VM.
- Keep the walkthrough to `/docs`, `/analyze`, and `/publish`; do not depend on a user-local `Downloads.zip` or invoke `/extract-downloads`.
- No database/cache, authentication, or secret setup is needed based on repository inspection.
- Do not modify application code.

# Technical Design

### Current Implementation
`src/api/main.py` exposes `/extract-downloads`, `/analyze`, and `/publish` via FastAPI. It instantiates `Logia` for each request; `/analyze` and `/publish` are stubs returning success responses. `README.md` documents launching with Uvicorn, and `pyproject.toml` requires Python >=3.13 with dependencies locked in `uv.lock`. The extraction endpoint ultimately expects `Downloads.zip` in a user's Downloads folder, so the confirmed demo scope excludes it. The repository currently has no `.junie/demo.md` or `.junie/vms/template-vm/`.

### Proposed Changes
Create demo configuration only. In `.junie/demo.md`, document the confirmed launch command, port/readiness signal, and a walkthrough limited to routes that need no host-local archive. In `.junie/vms/template-vm/Dockerfile`, preserve the required demo base image and add only the Python >=3.13 and `uv` provisioning needed to run the command. No runtime service or secret mounts are required.

# Testing

### Validation Approach
- Build the VM image from the project root using `.junie/vms/template-vm/Dockerfile`.
- Confirm the image provides Python >=3.13 and `uv`.
- Run the documented dependency sync and API command in the image; verify `http://localhost:8000/docs` responds successfully.
- Check `/analyze` and `/publish` return their current success responses without requiring additional services or data.

# Delivery Steps

### ✓ Step 1: Add VM demo instructions
The demo guide documents the agreed launch flow and archive-independent API walkthrough.

- Create `.junie/demo.md` with `vm: template-vm`.
- Document `uv sync` and `uv run uvicorn src.api.main:app --host 0.0.0.0` as the launch commands from `/workspace`.
- Specify port `8000` and `/docs` responding successfully as the readiness signal.
- Limit walkthrough coverage to `/docs`, `/analyze`, and `/publish`; note that `/extract-downloads` is intentionally excluded because it depends on a user-local ZIP.

### ✓ Step 2: Provision the demo VM runtime
The template VM image can execute UFV with its required Python and package manager.

- Create `.junie/vms/template-vm/Dockerfile` using the official demo base image as its `FROM`.
- Add the minimum layers needed to provide Python >=3.13 and `uv`, without adding unrelated services or secrets.
- Build the image from the project root and correct any clear, certain Dockerfile issue.

### ! Step 3: Smoke-test the documented API flow
The image satisfies the documented startup and API readiness expectations.

- Verify Python and `uv` versions inside the built image.
- Run dependency synchronization and start the API using the documented command.
- Confirm `/docs` is reachable on port `8000` and the `/analyze` and `/publish` routes return their current success responses.