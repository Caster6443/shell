"""Reject exact duplicate MP3 audio packets, ignoring filenames, tags and artwork."""
import subprocess
import sys
from pathlib import Path


def audio_hash(path):
    result = subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-i", str(path), "-map", "0:a:0",
         "-c", "copy", "-f", "hash", "-hash", "sha256", "-"],
        capture_output=True, text=True, timeout=30, check=True,
    )
    digest = result.stdout.strip()
    if not digest.startswith("SHA256="):
        raise ValueError("没有取得音频校验值")
    return digest


def check(source, directory):
    fingerprint = audio_hash(source)
    directory = Path(directory)
    if not directory.is_dir():
        raise ValueError("保存目录不存在")
    for candidate in sorted(directory.rglob("*")):
        if candidate.is_file() and candidate.suffix.lower() == ".mp3" and candidate.resolve() != source.resolve():
            if audio_hash(candidate) == fingerprint:
                print(f"音频与已有《{candidate.stem}》完全相同，已阻止另存；请核对网页分P链接")
                return 2
    return 0


if __name__ == "__main__":
    try:
        code = check(Path(sys.argv[1]), sys.argv[2])
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("无法完成音频重复检查，未保存歌曲；请检查音频文件和保存目录")
        print(str(error), file=sys.stderr)
        code = 1
    sys.exit(code)
