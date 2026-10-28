from fastapi import FastAPI
from src.etl.logia import Logia

app = FastAPI()


@app.get("/extract-downloads")
def extract_downloads():
    logia = Logia()
    return logia.extract_downloads(
    )


@app.get("/analyze")
def run_analysis():
    logia = Logia()
    return logia.analyze()


@app.get("/publish")
def run_publish():
    logia = Logia()
    return logia.publish()


