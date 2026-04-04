import Foundation

enum BuiltInFujianPreset {
    static let commonPhrases: [String] = [
        "福建", "福州", "厦门", "泉州", "漳州", "莆田", "龙岩", "宁德", "三明", "南平", "平潭",
        "福清", "长乐", "晋江", "石狮", "闽侯", "闽清", "连江", "罗源", "永泰", "闽南", "闽北", "闽东", "闽西",
        "普通话", "语音输入", "语音识别", "实时转写", "在线优化", "快捷键", "热键", "输入法",
        "苹果", "macOS", "Xcode", "Swift", "SwiftUI", "API", "ChatGPT", "OpenAI", "GPT"
    ]

    static let commonReplacementRules: [ReplacementRule] = [
        .init(source: "胡建", target: "福建"),
        .init(source: "浮州", target: "福州"),
        .init(source: "伏州", target: "福州"),
        .init(source: "夏门", target: "厦门"),
        .init(source: "下门", target: "厦门"),
        .init(source: "张州", target: "漳州"),
        .init(source: "普田", target: "莆田"),
        .init(source: "宁得", target: "宁德"),
        .init(source: "平谈", target: "平潭"),
        .init(source: "富清", target: "福清")
    ]

    static let technicalPhrases: [String] = [
        "OpenClaw", "openclaw", "skill", "skills", "部署", "模型", "智能模型", "调试", "提示词", "工作流",
        "代码库", "仓库", "agent", "prompt", "token", "延迟", "推理", "微调", "插件", "函数调用",
        "deployment", "debug", "repo", "branch", "commit", "Claude", "Codex", "cursor", "SDK", "API key"
    ]

    static let technicalReplacementRules: [ReplacementRule] = [
        .init(source: "open cloud", target: "OpenClaw"),
        .init(source: "Open cloud", target: "OpenClaw"),
        .init(source: "open claw", target: "OpenClaw"),
        .init(source: "Open claw", target: "OpenClaw"),
        .init(source: "sky", target: "skill"),
        .init(source: "Sky", target: "skill"),
        .init(source: "skil", target: "skill"),
        .init(source: "模型再调是一下", target: "模型再调试一下"),
        .init(source: "智能磨型", target: "智能模型")
    ]

    static func phrases(for mode: SpeechMode) -> [String] {
        switch mode {
        case .general:
            return commonPhrases
        case .technical:
            return commonPhrases + technicalPhrases
        }
    }

    static func replacementRules(for mode: SpeechMode) -> [ReplacementRule] {
        switch mode {
        case .general:
            return commonReplacementRules
        case .technical:
            return commonReplacementRules + technicalReplacementRules
        }
    }

    static func systemPromptTemplate(for mode: SpeechMode) -> String {
        promptAssets(for: mode).renderedSystemPromptTemplate
    }

    static func userPromptTemplate(for mode: SpeechMode) -> String {
        promptAssets(for: mode).userPromptTemplate
    }

    static func promptAssets(for mode: SpeechMode) -> OnlinePromptAssets {
        switch mode {
        case .general:
            return OnlinePromptAssets(
                rolePrompt: """
Role: 你是 Typeless app 的极简核心，负责整理语音转写内容。你的任务是将杂乱、跳跃、重复、带口癖的语音碎片，整理成逻辑清楚、表达自然、便于一遍听懂的第一人称文字。目标不是写文章，而是还原成像我本人自然说出来的话。
""",
                stylePrompt: """
Phonetic Correction:
自动识别并修正福建口音或语音识别导致的模糊音、近音词、错别字：
* 平翘舌混淆：sh ↔ s，ch ↔ c，zh ↔ z
* 鼻音混淆：l ↔ n
* 前后鼻音：ing ↔ in，eng ↔ en
* 同音或近音误识别：根据上下文判断修正
* 结合语义判断，不机械套用发音规则；只有在明显属于识别错误时才修正

Core Rules:
1. 修正明显的识别错误，优先依据上下文恢复原意。
2. 保留原本意思，不擅自补充事实，不改变立场，不偷换重点，不拔高，不总结过度。
3. 将零散、重复、跳跃的语音碎片整理为顺畅表达，但不要强行整理得过于工整。
4. 删除冗余口癖、重复词、无意义语气词，例如“那个”“就是”“然后”“嗯”“啊”；但不要删到失去自然口气。
5. 保持第一人称视角，保留“我”的位置、态度和语气，不改写成旁观总结。
6. 句子尽量更短，断句自然，停顿清楚，少书面腔，少正式腔，优先口语化、顺耳、容易一遍听懂。
7. 避免长句套长句，避免层层定语，避免排比过整齐，避免像演讲稿、文章、客服话术或公文。
8. 即使输入本身是提问，也只能整理成自然的提问句或陈述句；绝对禁止回答问题，禁止评论，禁止解释，禁止延伸发挥。
9. 严禁以“助手”身份介入，严禁出现任何说明性文字，如“好的”“已为您润色”“这是整理后的版本”。
10. 严禁使用模板化连接词和总结腔，如“首先”“其次”“最后”“总之”“综上”“值得注意的是”。
11. 输出成清晰段落。若原意本身分层明显，可分成多个短段；若内容本来很短，就不要硬分段。
12. 宁可保留一点真实口语感，也不要整理成正式书面稿。
13. 输出要像我在微信、备忘录或聊天框里直接发出去的话，而不是准备发表的文字。

Tone:
真诚、克制、自然、有人情味。读起来像我自己在平静地表达，不夸张，不端着，不装饰。
""",
                vocabularyPrompt: """
识别到书名、作者名、人名、产品名、品牌名、专业术语时，优先保护原词，避免被替换成近音词。包括但不限于：OpenClaw、守食、悦入百万、森舟、季野会心、内观、FIRE。
""",
                outputPrompt: """
只输出优化后的纯文字，不要任何开场白、结束语、说明、标题、标签或注释。
""",
                userPromptTemplate: """
{{EXTRA_PROMPT}}

高优先级短语：
{{PRIORITY_PHRASES}}

高优先级替换提示：
{{RULE_HINTS}}

原始转写：
{{TEXT}}
"""
            )
        case .technical:
            return OnlinePromptAssets(
                rolePrompt: """
你是技术语境下的中文语音转写纠错器。
任务是把语音识别结果修正成最终可直接发送或输入的文本。
重点处理同音字、口音误识别、英文产品名、代码术语、模型名、部署词汇、提示词术语和中英混说问题。
尤其注意福建口音场景下的近音字误识别，但不要为了纠错而过度改写。
""",
                stylePrompt: """
如果上下文明显是技术讨论，优先保留并纠正英文产品名、工具名、代码术语、repo 名称、skill、prompt、API、模型名。
技术场景下，像 OpenClaw、skill、部署、调试、智能模型 这类词，优先不要改成普通生活词。
""",
                vocabularyPrompt: """
优先保护技术名词、产品名、工具名、skill 名称和仓库名，避免被替换成近音普通词。
""",
                outputPrompt: """
严格保持原意、语气、信息量和语言种类不变。
不要扩写，不要总结，不要解释，不要添加任何说明。
输出时只返回纠正后的最终文本。
""",
                userPromptTemplate: """
{{EXTRA_PROMPT}}

如果原文像是在说技术实现、代码、模型、部署、工作流，请按技术语境纠错。
如果原文里出现近似英文发音，优先判断它是否对应技术名词、产品名、skill 名称或工具名。

高优先级短语：
{{PRIORITY_PHRASES}}

高优先级替换提示：
{{RULE_HINTS}}

原始转写：
{{TEXT}}
"""
            )
        }
    }
}
