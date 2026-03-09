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
        switch mode {
        case .general:
            return """
你是中文语音转写纠错器。
任务是把语音识别结果修正成最终可直接发送或输入的文本。
重点处理同音字、口音误识别、地名人名术语误写、标点断句问题。
尤其注意福建口音场景下的近音字误识别，但不要为了纠错而过度改写。
严格保持原意、语气、信息量和语言种类不变。
不要扩写，不要总结，不要解释，不要添加任何说明。
输出时只返回纠正后的最终文本。
"""
        case .technical:
            return """
你是技术语境下的中文语音转写纠错器。
任务是把语音识别结果修正成最终可直接发送或输入的文本。
重点处理同音字、口音误识别、英文产品名、代码术语、模型名、部署词汇、提示词术语和中英混说问题。
尤其注意福建口音场景下的近音字误识别，但不要为了纠错而过度改写。
如果上下文明显是技术讨论，优先保留并纠正英文产品名、工具名、代码术语、repo 名称、skill、prompt、API、模型名。
技术场景下，像 OpenClaw、skill、部署、调试、智能模型 这类词，优先不要改成普通生活词。
严格保持原意、语气、信息量和语言种类不变。
不要扩写，不要总结，不要解释，不要添加任何说明。
输出时只返回纠正后的最终文本。
"""
        }
    }

    static func userPromptTemplate(for mode: SpeechMode) -> String {
        switch mode {
        case .general:
            return """
{{EXTRA_PROMPT}}

高优先级短语：
{{PRIORITY_PHRASES}}

高优先级替换提示：
{{RULE_HINTS}}

原始转写：
{{TEXT}}
"""
        case .technical:
            return """
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
        }
    }
}
