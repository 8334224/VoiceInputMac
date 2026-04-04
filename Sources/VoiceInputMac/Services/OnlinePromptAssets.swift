import Foundation

struct OnlinePromptAssets: Equatable, Codable, Sendable {
    var rolePrompt: String
    var stylePrompt: String
    var vocabularyPrompt: String
    var outputPrompt: String
    var userPromptTemplate: String

    init(
        rolePrompt: String,
        stylePrompt: String,
        vocabularyPrompt: String,
        outputPrompt: String,
        userPromptTemplate: String
    ) {
        self.rolePrompt = rolePrompt
        self.stylePrompt = stylePrompt
        self.vocabularyPrompt = vocabularyPrompt
        self.outputPrompt = outputPrompt
        self.userPromptTemplate = userPromptTemplate
    }

    var renderedSystemPromptTemplate: String {
        [
            rolePrompt,
            stylePrompt,
            vocabularyPrompt,
            outputPrompt
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    static func legacy(systemPrompt: String, userPromptTemplate: String) -> OnlinePromptAssets {
        OnlinePromptAssets(
            rolePrompt: systemPrompt,
            stylePrompt: "",
            vocabularyPrompt: "",
            outputPrompt: "",
            userPromptTemplate: userPromptTemplate
        )
    }
}
