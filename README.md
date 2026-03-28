# VoiceInputMac

VoiceInputMac is an open-source macOS menu bar voice input tool focused on one problem:

- improving first-pass speech-to-text accuracy

The project is intentionally not centered on chat, summarization, or full-document rewriting. Its main goal is to make local dictation on macOS more reliable, especially for Chinese speech input and real-world short-form text entry.

## What the project does

VoiceInputMac currently provides:

- a macOS menu bar app with global hotkey start/stop dictation
- local microphone capture with session-level audio caching
- manual microphone device selection
- automatic microphone list refresh on hotplug and default-input changes
- visible recording-session input device status in the menu bar and settings
- structured transcript segments instead of plain text only
- rule-based suspicious-span detection
- local clip extraction for partial re-recognition
- multi-backend re-recognition experiments
- candidate evaluation, comparison, and experiment export
- optional post-pass online optimization
- automatic paste into the active app

## Current architecture

The current recognition stack is split into reusable layers:

- `AudioCaptureService`
  - microphone capture
  - explicit input-device binding without changing the system-wide default input
  - session audio caching
  - clip extraction by time range
- `MicrophoneDeviceService` / device monitors
  - input-device enumeration
  - hotplug refresh
  - system default input change refresh
- `RecognitionBackend`
  - Apple Speech for the main dictation path
  - Apple Speech on-device, WhisperKit, and SenseVoice-Small for experimental local re-recognition / baseline comparison
- `TextPostProcessor`
  - local phrase correction
  - conservative post-processing
- `SuspicionDetector`
  - marks likely bad spans in the first-pass transcript
- `ReRecognitionPlanner`
  - chooses which suspicious spans are worth re-running
- `ReRecognitionEvaluator`
  - scores alternative candidates using rule-based quality signals
- `CandidateResolver`
  - compares backend candidates and summarizes experiment outcomes

## Main project direction

This repository is being developed as a practical experimentation platform for:

- fixed-language Chinese recognition
- hotwords and custom lexicons
- suspicious segment detection
- localized re-recognition instead of full-text rewriting
- backend comparison for difficult spans
- repeatable regression testing for transcription quality

## Why this repository exists

Most speech products optimize for convenience after recognition. This project is biased toward a different goal:

- reduce errors in the first transcription pass

That leads to a different engineering focus:

- segment-level metadata
- replayable audio windows
- suspicious-span planning
- candidate comparison
- repeatable experiment export

## Current status

The project is usable as a macOS voice input shell and an active experimentation platform for recognition quality work.

What is already implemented:

- menu bar app
- settings storage
- global hotkey control
- microphone permissions and accessibility flow
- microphone device selection with persistence and restart restore
- microphone hotplug refresh and system default input auto-refresh
- visible active input device name while recording
- Apple Speech main dictation path
- experimental WhisperKit and SenseVoice-Small local paths
- structured JSON export for repeatable experiments

What is still evolving:

- stronger Chinese suspicious-span rules
- more stable backend divergence signals
- better ranking for near-correct Chinese candidates
- more fixed-audio regression coverage

## Running locally

In the project root:

```bash
swift build
swift run VoiceInputMac
```

If you want to build the app bundle:

```bash
./scripts/build_app.sh
```

Output:

- `dist/VoiceInputMac.app`

Beta install and distribution notes:

- [`docs/BetaInstall.md`](docs/BetaInstall.md)
- [`docs/ReleaseSigning.md`](docs/ReleaseSigning.md)

## Permissions

The app requires:

- Microphone
- Speech Recognition
- Accessibility

Accessibility is used for text insertion into the active application.

The Beta build also supports:

- choosing a specific microphone instead of always following the system default
- automatically detecting microphone plug/unplug events
- automatically refreshing when macOS switches the default input device
- showing which input device the current recording session is actually using

## Fixed-audio experiment entry

The repository also includes a minimal fixed-audio experiment entry for repeatable testing.

Example:

```bash
VOICEINPUT_FIXED_AUDIO_PATH="/absolute/path/to/sample.m4a" \
VOICEINPUT_FIXED_AUDIO_MODE="blended" \
VOICEINPUT_FIXED_AUDIO_SAMPLE_LABEL="long_sentence" \
VOICEINPUT_FIXED_AUDIO_SESSION_TAG="sample-01" \
swift test --filter FixedAudioExperimentRunnerTests/testRunLocalAudioExperimentFromEnvironment
```

Exported experiment JSON files are saved to:

- `~/Library/Application Support/VoiceInputMac/ReRecognitionExperiments`

## Roadmap

Near-term priorities:

- improve Chinese first-pass error detection
- improve candidate evaluation for near-correct Chinese outputs
- expand fixed-audio regression testing
- compare Apple Speech and SenseVoice-Small on a broader first-pass baseline set
- identify samples that produce meaningful backend ordering differences

Mid-term priorities:

- stronger hotword and user lexicon management
- more reliable local re-recognition scheduling
- better promotion criteria for partial candidate replacement

## Contributing

Contributions are welcome, especially in:

- macOS / Swift / SwiftUI engineering
- speech recognition evaluation
- Chinese transcription quality analysis
- reproducible test samples
- fixed-audio regression workflows

Useful contribution types:

- bug reports with exported experiment JSON
- fixed-audio samples that expose backend differences
- improvements to suspicious-span rules
- improvements to candidate evaluation logic

## Repository focus

This repository should be read as:

- a real macOS utility
- an active OSS speech-quality experiment platform
- a codebase focused on first-pass dictation quality, not assistant-style text rewriting
