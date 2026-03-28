#!/usr/bin/env python3

import argparse
import json
import sys
from pathlib import Path

from funasr_onnx import SenseVoiceSmall
from funasr_onnx.utils.postprocess_utils import rich_transcription_postprocess


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Transcribe one audio file with SenseVoice-Small.")
    parser.add_argument("--model-dir", required=True, help="Local SenseVoice-Small model directory.")
    parser.add_argument("--audio-path", required=True, help="Audio file path.")
    parser.add_argument("--language", default="auto", help="SenseVoice language code, e.g. zh/en/auto.")
    parser.add_argument("--use-itn", action="store_true", help="Enable inverse text normalization.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    model_dir = Path(args.model_dir).expanduser().resolve()
    audio_path = Path(args.audio_path).expanduser().resolve()

    if not model_dir.exists():
        print(json.dumps({"error": f"model directory not found: {model_dir}"}), file=sys.stderr)
        return 2

    if not audio_path.exists():
        print(json.dumps({"error": f"audio file not found: {audio_path}"}), file=sys.stderr)
        return 3

    model = SenseVoiceSmall(str(model_dir), batch_size=1, quantize=False)
    raw_results = model([str(audio_path)], language=args.language, use_itn=args.use_itn)
    raw_text = raw_results[0] if raw_results else ""
    text = rich_transcription_postprocess(raw_text).strip()

    print(
        json.dumps(
            {
                "text": text,
                "raw_text": raw_text,
                "language": args.language,
                "model_dir": str(model_dir),
                "audio_path": str(audio_path),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
