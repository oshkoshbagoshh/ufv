from __future__ import annotations

import hashlib
import mimetypes
import re
from collections import defaultdict
from dataclasses import asdict, dataclass
from difflib import SequenceMatcher
from pathlib import Path
from typing import Iterable
from zipfile import BadZipFile, ZipFile

DEFAULT_MIME_TYPE = "application/octet-stream"
DIRECTORY_MIME_TYPE = "inode/directory"
DEFAULT_HASH_CHUNK_SIZE = 1024 * 1024
DEFAULT_DOWNLOADS_ZIP_NAME = "Downloads.zip"


def _serializable_path_dict(instance: object) -> dict:
    data = asdict(instance)
    data["path"] = str(data["path"])
    data["relative_path"] = str(data["relative_path"])
    return data


@dataclass(frozen=True)
class FileInfo:
    path: Path
    relative_path: Path
    name: str
    suffix: str
    size_bytes: int
    is_file: bool
    is_dir: bool

    def to_dict(self) -> dict:
        return _serializable_path_dict(self)


@dataclass(frozen=True)
class FileInventoryItem:
    path: Path
    relative_path: Path
    name: str
    normalized_name: str
    suffix: str
    mime_type: str
    mime_group: str
    size_bytes: int
    sha256: str | None
    is_file: bool
    is_dir: bool

    def to_dict(self) -> dict:
        return _serializable_path_dict(self)


def find_project_root(start: str | Path | None = None, marker: str = "pyproject.toml") -> Path:
    current = standardize_path(start or Path.cwd())

    for path in [current, *current.parents]:
        if (path / marker).exists():
            return path

    raise RuntimeError(f"Could not find project root containing {marker!r}")


def standardize_path(path: str | Path, base_dir: str | Path | None = None) -> Path:
    resolved_path = Path(path).expanduser()

    if not resolved_path.is_absolute() and base_dir is not None:
        resolved_path = Path(base_dir).expanduser() / resolved_path

    return resolved_path.resolve()


def ensure_directory(path: str | Path) -> Path:
    directory = standardize_path(path)
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def _validate_directory(directory: str | Path) -> Path:
    resolved_directory = standardize_path(directory)

    if not resolved_directory.exists():
        raise FileNotFoundError(f"Directory does not exist: {resolved_directory}")

    if not resolved_directory.is_dir():
        raise NotADirectoryError(f"Path is not a directory: {resolved_directory}")

    return resolved_directory


def _iter_directory_paths(directory: Path, recursive: bool) -> Iterable[Path]:
    return directory.rglob("*") if recursive else directory.iterdir()


def _build_file_info(path: Path, root_directory: Path) -> FileInfo:
    is_file = path.is_file()

    return FileInfo(
        path=path,
        relative_path=path.relative_to(root_directory),
        name=path.name,
        suffix=path.suffix.lower(),
        size_bytes=path.stat().st_size if is_file else 0,
        is_file=is_file,
        is_dir=path.is_dir(),
    )


def list_file_info(directory: str | Path, recursive: bool = True) -> list[FileInfo]:
    root_directory = _validate_directory(directory)

    return [
        _build_file_info(path, root_directory)
        for path in sorted(_iter_directory_paths(root_directory, recursive))
    ]


def _validate_zip_member_paths(zip_file: ZipFile, destination: Path) -> None:
    resolved_destination = destination.resolve()

    for member in zip_file.infolist():
        resolved_member_path = (resolved_destination / member.filename).resolve()

        if not resolved_member_path.is_relative_to(resolved_destination):
            raise ValueError(f"Unsafe zip member path detected: {member.filename}")


def extract_zip(
        zip_path: str | Path,
        destination: str | Path,
        *,
        overwrite: bool = False,
) -> list[FileInfo]:
    resolved_zip_path = standardize_path(zip_path)
    resolved_destination = ensure_directory(destination)

    if not resolved_zip_path.exists():
        raise FileNotFoundError(f"Zip file does not exist: {resolved_zip_path}")

    if not resolved_zip_path.is_file():
        raise ValueError(f"Zip path is not a file: {resolved_zip_path}")

    if resolved_zip_path.suffix.lower() != ".zip":
        raise ValueError(f"Expected a .zip file, got: {resolved_zip_path}")

    try:
        with ZipFile(resolved_zip_path, "r") as zip_file:
            _validate_zip_member_paths(zip_file, resolved_destination)

            for member in zip_file.infolist():
                target_path = resolved_destination / member.filename

                if target_path.exists() and not overwrite:
                    continue

                zip_file.extract(member, resolved_destination)

    except BadZipFile as exc:
        raise ValueError(f"Invalid or corrupted zip file: {resolved_zip_path}") from exc

    return list_file_info(resolved_destination, recursive=True)


def extract_downloads_zip(
        downloads_zip_path: str | Path | None = None,
        *,
        project_root: str | Path | None = None,
        output_dir: str | Path = "data/downloads",
        overwrite: bool = False,
) -> list[FileInfo]:
    root = standardize_path(project_root) if project_root else find_project_root()
    zip_path = downloads_zip_path or Path.home() / "Downloads" / DEFAULT_DOWNLOADS_ZIP_NAME
    destination = standardize_path(output_dir, base_dir=root)

    return extract_zip(
        zip_path=zip_path,
        destination=destination,
        overwrite=overwrite,
    )


def file_infos_to_dicts(file_infos: list[FileInfo]) -> list[dict]:
    return [file_info.to_dict() for file_info in file_infos]


def normalize_file_name(name: str) -> str:
    stem = Path(name).stem.lower()
    stem = re.sub(r"\(\d+\)$", "", stem)
    stem = re.sub(r"[-_\s]+", " ", stem)
    stem = re.sub(r"[^a-z0-9 ]+", "", stem)
    return stem.strip()


def guess_mime_type(path: str | Path) -> str:
    mime_type, _ = mimetypes.guess_type(str(path))
    return mime_type or DEFAULT_MIME_TYPE


def mime_group(mime_type: str) -> str:
    if "/" not in mime_type:
        return "unknown"

    return mime_type.split("/", 1)[0]


def sha256_file(path: str | Path, chunk_size: int = DEFAULT_HASH_CHUNK_SIZE) -> str:
    resolved_path = standardize_path(path)
    digest = hashlib.sha256()

    with resolved_path.open("rb") as file:
        for chunk in iter(lambda: file.read(chunk_size), b""):
            digest.update(chunk)

    return digest.hexdigest()


def _build_inventory_item(
        path: Path,
        root_directory: Path,
        *,
        hash_files: bool,
) -> FileInventoryItem:
    is_file = path.is_file()
    is_dir = path.is_dir()
    item_mime_type = guess_mime_type(path) if is_file else DIRECTORY_MIME_TYPE

    return FileInventoryItem(
        path=path,
        relative_path=path.relative_to(root_directory),
        name=path.name,
        normalized_name=normalize_file_name(path.name),
        suffix=path.suffix.lower(),
        mime_type=item_mime_type,
        mime_group=mime_group(item_mime_type),
        size_bytes=path.stat().st_size if is_file else 0,
        sha256=sha256_file(path) if is_file and hash_files else None,
        is_file=is_file,
        is_dir=is_dir,
    )


def inventory_files(
        directory: str | Path,
        *,
        recursive: bool = True,
        include_directories: bool = False,
        hash_files: bool = True,
) -> list[FileInventoryItem]:
    root_directory = _validate_directory(directory)
    inventory: list[FileInventoryItem] = []

    for path in sorted(_iter_directory_paths(root_directory, recursive)):
        if path.is_dir() and not include_directories:
            continue

        inventory.append(
            _build_inventory_item(
                path,
                root_directory,
                hash_files=hash_files,
            )
        )

    return inventory


def inventory_items_to_dicts(items: list[FileInventoryItem]) -> list[dict]:
    return [item.to_dict() for item in items]


def group_inventory_by_mime_type(items: list[FileInventoryItem]) -> dict[str, list[dict]]:
    grouped: dict[str, list[dict]] = defaultdict(list)

    for item in items:
        grouped[item.mime_type].append(item.to_dict())

    return dict(sorted(grouped.items(), key=lambda entry: entry[0]))


def summarize_by_mime_type(items: list[FileInventoryItem]) -> list[dict]:
    summary: dict[str, dict] = {}

    for item in items:
        if not item.is_file:
            continue

        bucket = summary.setdefault(
            item.mime_type,
            {
                "mime_type": item.mime_type,
                "mime_group": item.mime_group,
                "file_count": 0,
                "total_size_bytes": 0,
            },
        )
        bucket["file_count"] += 1
        bucket["total_size_bytes"] += item.size_bytes

    return sorted(summary.values(), key=lambda entry: entry["mime_type"])


# def analyze_downloads_folder():
#     return None