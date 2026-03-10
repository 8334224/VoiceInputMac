# 固定音频回归集

这组回归样本用于在不改录音方式的前提下，重复检查：

- 主路径首轮转写是否变好或变坏
- 中文局部错词与拆分型错误是否还能进入 `planner`
- 多 backend 候选比较是否还存在
- `backendComparisons` / `backendDivergence` / `orderEffectiveness` 是否出现异常回退

## 最小回归集

| ID | 本地音频文件 | 推荐 `sampleLabel` | 主要覆盖点 |
| --- | --- | --- | --- |
| `REG-01` | `/Users/adi/Desktop/Shuanghan Road.m4a` | `long_sentence` | 中文常用短句、中文拆分型错误、主路径 vs WhisperKit 比较 |
| `REG-02` | `/Users/adi/Desktop/Shuanghan Road 2.m4a` | `english_abbreviation` | 中英混说、热词周边中文搭配、`API` 场景 |
| `REG-03` | `/Users/adi/Desktop/New Recording.m4a` | `long_sentence` | 中文局部错词、`部署系统` / `转写成文字` 场景 |
| `REG-04` | `/Users/adi/Downloads/Shuanghan Road 4.m4a` | `long_sentence` | 已验证可进入 comparison，当前最接近顺序策略样本 |
| `REG-05` | `/Users/adi/Downloads/嘉禾路384号.m4a` | `number_unit` | 数字、中文地址、编号类口述 |
| `REG-06` | `/Users/adi/Downloads/Huli Avenue 22 Haolian Fawen Chuangkou'an Room 212-213 2.m4a` | `number_unit` | 地址、英文路名、数字串、中英混说 |

## 每条样本建议观察点

### `REG-01` `/Users/adi/Desktop/Shuanghan Road.m4a`

预期优先看：

- `transcript.displayText`
- `planCount`
- `backendComparisons[].hasTextDivergence`
- `backendComparisons[].hasScoreDivergence`

这条样本已经验证过会进入 comparison，适合做“固定基线样本”。

### `REG-02` `/Users/adi/Desktop/Shuanghan Road 2.m4a`

预期优先看：

- `API` 是否稳定保留
- `开放给外部用户` 这类热词周边短语有没有被拆坏
- `planCount` 是否仍然经常为 `0`

这条更适合做“首轮准确率和热词稳定性”基线，不一定稳定进入局部重识别。

### `REG-03` `/Users/adi/Desktop/New Recording.m4a`

预期优先看：

- `部署系统`
- `转写成文字`
- 是否出现中文局部错词或拆分

这条适合覆盖中文实词近音错词与拆分型错误的回归。

### `REG-04` `/Users/adi/Downloads/Shuanghan Road 4.m4a`

预期优先看：

- `bestFromNonFirstBackendCount`
- `recommendedReadyForReviewCount`
- `backendComparisons`
- `orderEffectiveness.overall`

这条是当前最值得保留的“顺序策略观察样本”，即使它还没稳定到每次都拉开三模式差异。

### `REG-05` `/Users/adi/Downloads/嘉禾路384号.m4a`

预期优先看：

- 数字是否稳定
- 地址类中文是否完整
- `384` 这类数字是否被吞掉或改写

这条主要用于数字和地址类回归。

### `REG-06` `/Users/adi/Downloads/Huli Avenue 22 Haolian Fawen Chuangkou'an Room 212-213 2.m4a`

预期优先看：

- 路名/地名的中英混排
- `22`、`212-213` 这类数字串
- 是否出现英文段整体跑偏

这条主要用于中英混说和数字串回归。

## 命名规则

建议把导出的 `sessionTag` 固定成：

- `reg-01-fixed`
- `reg-01-session`
- `reg-01-blended`
- `reg-02-fixed`
- ...

建议保持：

- 文件 ID 固定
- 只改变 `currentOrderMode`
- 每轮只新增一个清晰后缀

这样导出 JSON 会稳定形成：

- `reg-01-fixed__fixed__YYYYMMDD-HHMMSS.json`
- `reg-01-session__session__YYYYMMDD-HHMMSS.json`
- `reg-01-blended__blended__YYYYMMDD-HHMMSS.json`

## 如何复跑

### 单条复跑

在 `/Users/adi/Desktop/语音输入法` 下执行：

```bash
VOICEINPUT_FIXED_AUDIO_PATH="/Users/adi/Desktop/Shuanghan Road.m4a" \
VOICEINPUT_FIXED_AUDIO_MODE="blended" \
VOICEINPUT_FIXED_AUDIO_SAMPLE_LABEL="long_sentence" \
VOICEINPUT_FIXED_AUDIO_SESSION_TAG="reg-01-blended" \
swift test --filter FixedAudioExperimentRunnerTests/testRunLocalAudioExperimentFromEnvironment
```

### 半批量复跑

可以按模式分批跑，例如先把 6 条样本全跑一遍 `blended`：

```bash
cd /Users/adi/Desktop/语音输入法

while IFS='|' read -r session_tag sample_label audio_path; do
  VOICEINPUT_FIXED_AUDIO_PATH="$audio_path" \
  VOICEINPUT_FIXED_AUDIO_MODE="blended" \
  VOICEINPUT_FIXED_AUDIO_SAMPLE_LABEL="$sample_label" \
  VOICEINPUT_FIXED_AUDIO_SESSION_TAG="$session_tag" \
  swift test --filter FixedAudioExperimentRunnerTests/testRunLocalAudioExperimentFromEnvironment
done <<'EOF'
reg-01-blended|long_sentence|/Users/adi/Desktop/Shuanghan Road.m4a
reg-02-blended|english_abbreviation|/Users/adi/Desktop/Shuanghan Road 2.m4a
reg-03-blended|long_sentence|/Users/adi/Desktop/New Recording.m4a
reg-04-blended|long_sentence|/Users/adi/Downloads/Shuanghan Road 4.m4a
reg-05-blended|number_unit|/Users/adi/Downloads/嘉禾路384号.m4a
reg-06-blended|number_unit|/Users/adi/Downloads/Huli Avenue 22 Haolian Fawen Chuangkou'an Room 212-213 2.m4a
EOF
```

再把同样的 `sessionTag` 前缀改成 `fixed` 或 `session`，就能做三模式对比。

## 导出位置

固定音频法导出的 JSON 保持不变，仍然写到：

- `~/Library/Application Support/VoiceInputMac/ReRecognitionExperiments`

## 最低检查清单

每次复跑后，至少检查：

- `transcript.displayText`
- `planCount`
- `backendComparisons`
- `backendDivergence`
- `orderEffectiveness.overall`

如果目标是顺序策略比较，再额外看：

- `recommendedBecameBestRatio`
- `recommendedReadyForReviewRatio`
- `firstTriedBecameBestRatio`
- `bestFromNonFirstBackendRatio`
