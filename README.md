# UFV ETL System

This project implements a repeatable ETL system using Jupyter notebooks for development/analysis and FastAPI for serving.

## Structure
- `src/etl/`: Contains the core ETL logic (`Logia` class).
- `src/api/`: Contains the FastAPI application.
- `notebooks/`: Contains Jupyter notebooks for developing and running ETL processes.

## Getting Started
1. Install dependencies (e.g., using `pip` or `uv`):
   ```bash
   pip install fastapi uvicorn pandas jupyter
   ```
2. Run the FastAPI application:
   ```bash
   uvicorn src.api.main:app --reload
   ```
3. Use notebooks in `notebooks/` to run and test ETL logic.
