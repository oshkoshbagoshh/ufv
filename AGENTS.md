# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

UFV is a repeatable ETL system. Core ETL logic lives in a single `Logia` class that is driven two ways from the same code path: interactively via Jupyter notebooks (development/analysis) and over HTTP via FastAPI (serving). Requires Python >=3.13; dependencies are managed with `uv` (see `uv.lock`).

## Commands

```bash
uv sync                                    # install dependencies from uv.lock
uv run uvicorn src.api.main:app --reload   # run the API (endpoints: GET /analyze, GET /publish)
uv run jupyter lab                         # open notebooks in notebooks/
```

There is no test suite or linter configured yet.

## Architecture

The ETL pipeline is defined once in `src/etl/logia.py` as `Logia`, with three stages meant to run in order:

- `extract(zip_path)` — unzips into `self.data_path` (defaults to `data/`, created on init)
- `analyze()` — returns a status dict
- `publish()` — returns a status dict

Two entry points wrap the same class:

- `src/api/main.py` — FastAPI app; each endpoint instantiates a fresh `Logia()` and calls one stage. Note endpoints are stateless per request, so `extract`'s output on disk is the only thing shared between calls.
- `notebooks/etl_template.ipynb` — imports `Logia` and runs `extract` → `analyze` → `publish` directly. This is the template for developing new ETL flows.

When adding pipeline functionality, add it as a method/stage on `Logia` so both the API and notebooks pick it up automatically, rather than duplicating logic in either entry point.

## Notes

- `analyze()` and `publish()` are currently stubs — they print and return a success dict without real logic.
- Root `main.py` is an unrelated placeholder stub, not part of the ETL system.
- Imports assume the repo root is the working directory (`from src.etl.logia import Logia`); run commands from the project root.
