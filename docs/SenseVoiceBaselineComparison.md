# SenseVoice 首轮基线对比

这份说明用于固定音频法下，直接比较：

- `apple.speech` 首轮整段结果
- `sensevoice.small` 首轮整段结果

它不走局部重识别，不依赖 `planner` 是否命中，适合回答两个问题：

- SenseVoice-Small 首轮到底比 Apple Speech 强不强
- 哪类样本更值得继续推进成“可选主识别后端”

## 运行方式

在 `/Users/adi/Desktop/语音输入法` 下执行：

```bash
VOICEINPUT_BASELINE_AUDIO_PATH="/absolute/path/to/sample.wav" \
VOICEINPUT_BASELINE_LOCALE="zh-CN" \
VOICEINPUT_BASELINE_SESSION_TAG="baseline-sample-01" \
swift test --filter FirstPassBackendComparisonRunnerTests/testRunFirstPassComparisonFromEnvironment
```

## 导出结果

导出 JSON 会写到：

- `~/Library/Application Support/VoiceInputMac/ReRecognitionExperiments`

文件名格式：

- `baseline-sample-01__first-pass__YYYYMMDD-HHMMSS.json`

## 导出字段

每份 JSON 至少包含：

- `sessionTag`
- `audioPath`
- `localeIdentifier`
- `results`

其中 `results` 会列出：

- `backend`
- `displayText`
- `rawText`
- `source`

## 推荐首批样本

建议优先用这些已有固定音频：

- `/Users/adi/Desktop/Shuanghan Road.m4a`
- `/Users/adi/Desktop/Shuanghan Road 2.m4a`
- `/Users/adi/Desktop/New Recording.m4a`
- `/Users/adi/Downloads/嘉禾路384号.m4a`
- `/Users/adi/Downloads/Huli Avenue 22 Haolian Fawen Chuangkou'an Room 212-213 2.m4a`

如果这些路径里有文件已经移动，先替换成当前实际路径。

## 最低对比方法

每条音频至少看这两列：

- `apple.speech`
- `sensevoice.small`

优先比较：

- 技术词是否更接近目标
- 中文数字是否更稳定
- 中英混说是否更自然
- 是否出现明显近音错词

## 什么时候值得继续推进

如果同一批样本里，`sensevoice.small` 在下列场景持续优于 `apple.speech`，就值得继续推进：

- 技术词
- 中英混说
- 中文长句
- 数字与地址

如果它只是偶尔更好，而大多数样本接近或更差，那更适合作为实验后端，不适合直接升成主链路候选。

## 当前已跑通的稳定样本

下面这 4 条是目前已经稳定跑通、可以复看的首轮基线样本。比较列包括：

- 闪电说 `original_text`
- 闪电说 `ai_corrected_text`
- `apple.speech`
- `sensevoice.small`

### 1. sv-docker

- 闪电说原始：
  - `我装过 Doc 的，装过虚拟机乌班图，现在用的是苹果的虚拟机。虚拟机苹果的又有两个版本。`
- 闪电说 AI：
  - `我装过 Docker，也装过虚拟机 Ubuntu。现下用的是苹果的虚拟机，这虚拟机又分作两个版本。`
- Apple：
  - `我装过稻壳的装过虚拟机乌斑图，现在用的是苹果的虚拟机苹果的有两个版本`
- SenseVoice：
  - `我装过 do的装过虚拟机乌班图现在用的是苹果的虚拟机洗李机苹果的又有两个版本`

判断：
- `SenseVoice-Small` 在技术词附近比 Apple 更接近目标。
- 但它仍然没有直接打到 `Docker / Ubuntu`。
- 闪电说最终观感明显还依赖 AI 修正，不只是首轮 ASR。

### 2. sv-timeout

- 闪电说原始：
  - `这个普通人可能不知道，我当时在做这个软件的时候，我就知道它有一个超时时间。因为如果等待太长了，用户体验非常差，所以它就会等待时间一超出，它就会改用本地的。`
- 闪电说 AI：
  - `这个一般人可能不知道。我当时做这个软件的时候，就知道它有个超时时间。因为等得太久，用户体验会很差。所以一旦超时，它就会改用本地的。`
- Apple：
  - `这个普通人可能不知道，我当时在做这个软件的时候，我就知道他有一个超时时间，因为如果等待太长了，用户体验非常差，所以他就会等待时间一超出他就会改用本地的`
- SenseVoice：
  - `这个普通人可能不知道我当时在做这个软件的时候我就知道他有一个超时时间因为如果等待太长了用户体验非常差所以他就会等待时间一超出他就会改用本地的`

判断：
- Apple 和 SenseVoice 基本打平。
- 这类普通中文长句目前看不出 SenseVoice 的明显优势。

### 3. sv-park

- 闪电说原始：
  - `明天去中山公园，记得带5包瓜子、3斤牛肉干，还有5瓶水。另外你自己喜欢吃什么，那就买一些。`
- 闪电说 AI：
  - `明天去中山公园，记得带5包瓜子，3斤牛肉干，还有5瓶水。另外你自己喜欢吃什么，也可以买点。`
- Apple：
  - `明天去中山公园，记得带五包瓜子，三斤牛肉干，还有五瓶水，另外你自己喜欢吃什么，那就买一些`
- SenseVoice：
  - `明天去中山公园记得带五包瓜子三斤牛肉干还有五瓶水另外你自己喜欢吃什么那就买一些`

判断：
- 普通中文加数字口述上，两者都能用。
- SenseVoice 没有明显碾压 Apple。

### 4. sv-uncle

- 闪电说原始：
  - `明天去叔叔家，我们要带一些礼物，带几斤水果，然后带一些坚果吧。他可能喜欢吃牛肉干，那也带一点。还有，你看看还有什么要补充的吗？`
- 闪电说 AI：
  - `明天去叔叔家，我们要带一些礼物：带几斤水果，再带些坚果。他可能喜欢吃牛肉干，也带一点。你看看还有什么要补充的吗？`
- Apple：
  - `明天去叔叔家，我们要带一些礼物带几斤水果，然后带一些坚果吧，他可能喜欢吃牛肉干，那也带一点，还有你看看还有什么要补充的吗？`
- SenseVoice：
  - `明天去叔叔家我们要带一些礼物带几斤水果然后带一些坚果吧她可能喜欢吃牛肉干那也带一点还有你看看还有什么要补充的吗`

判断：
- Apple 略好。
- SenseVoice 在中文代词上出错，说明它并不是在所有普通中文场景都更稳。

## 当前阶段结论

- `SenseVoice-Small` 已经值得继续推进成正式候选本地 backend。
- 但从目前稳定样本看，它还不够支持“直接替换 Apple Speech 主链路”。
- 它最值得继续验证的方向是：
  - 技术词
  - 中英混说
  - 专有名词附近的首轮识别
- 如果后续在一组更系统的固定音频样本里，它能稳定优于 Apple 2 到 3 类场景，再考虑把它升成可选主识别后端。
