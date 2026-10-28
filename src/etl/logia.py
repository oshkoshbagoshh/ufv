from pathlib import Path

from src.etl.files import (
    analyze_downloads_folder,
    extract_downloads_zip,
    extract_zip, file_infos_to_dicts,
    standardize_path,

)


class Logia:
    def __init__(self, data_path: str | Path = "data"):
        self.data_path = standardize_path(data_path)
        self.data_path.mkdir(parents=True, exist_ok=True)

    def extract(self, zip_path: str | Path):
        file_infos = extract_zip(
            zip_path=zip_path,
            destination=self.data_path,
            overwrite=False,
        )

        return {
            "status": "success",
            "message": f"Extracted {zip_path} to {self.data_path}",
            "data_path": str(self.data_path),
            "files": file_infos_to_dicts(file_infos),
        }

    def extract_downloads(self, downloads_zip_path: str | Path | None = None):
        file_infos = extract_downloads_zip(
            downloads_zip_path=downloads_zip_path,
            project_root=self.data_path.parent,
            output_dir=self.data_path / "downloads",
            overwrite=False,
        )

        return {
            "status": "success",
            "message": "Downloads.zip extracted successfully.",
            "data_path": str(self.data_path / "downloads"),
            "files": file_infos_to_dicts(file_infos),
        }

    def analyze_downloads(
        self,
        downloads_zip_path: str | Path | None = None,
        *,
        overwrite: bool = False,
        similarity_threshold: float = 0.88,
    ):
        downloads_dir = self.data_path / "downloads"

        extract_downloads_zip(
            downloads_zip_path=downloads_zip_path,
            project_root=self.data_path.parent,
            output_dir=downloads_dir,
            overwrite=overwrite,
        )

        analysis = analyze_downloads_folder(
            downloads_dir,
            recursive=True,
            hash_files=True,
            similarity_threshold=similarity_threshold,
        )

        return {
            "status": "success",
            "message": "Downloads folder extracted and analyzed successfully.",
            **analysis,
        }
    # TODO: replace stub, with Logia Data Analytics Class
            # TODO: build out.
                # PGadmin, etc.
                # data science team
                # accounting / finance calculations

    def analyze(self):
        print("Analysis complete.")
        return {"status": "success", "message": "Analysis complete"}


    # TODO: replace stub, with Logia Publicaation Class
        # Interace for either front end, or Wiki , or Internal Knowledge base
    def publish(self):
        print("Publishing complete.")
        return {"status": "success", "message": "Publish complete"}
