vm: template-vm

## Running inside the VM

From `/workspace`, install the locked dependencies and start the API:

    uv sync
    uv run uvicorn src.api.main:app --host 0.0.0.0 &
    # ready when http://localhost:8000/docs responds successfully

Use `/docs`, `/analyze`, and `/publish` for the walkthrough. Do not invoke `/extract-downloads`: it depends on a `Downloads.zip` in a user-local Downloads folder, which is not provided in the VM.
