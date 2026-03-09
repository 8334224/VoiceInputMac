import Foundation

struct OnlineOptimizer {
    enum OptimizationError: LocalizedError {
        case invalidConfiguration(String)
        case invalidEndpoint
        case server(statusCode: Int, message: String)
        case invalidResponse
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case let .invalidConfiguration(message):
                return message
            case .invalidEndpoint:
                return "接口地址无效。"
            case let .server(statusCode, message):
                return "服务端返回 \(statusCode)：\(message)"
            case .invalidResponse:
                return "接口返回格式无法识别。"
            case .emptyResponse:
                return "接口返回成功，但内容为空。"
            }
        }
    }

    struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double?
        let stream: Bool
    }

    struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    func optimize(_ text: String, settings: AppSettings, correctionPipeline: TextCorrectionPipeline) async throws -> String {
        guard settings.onlineOptimizationEnabled else { return text }

        return await withTaskGroup(of: String.self) { group in
            group.addTask {
                (try? await requestOptimizedText(text, settings: settings, correctionPipeline: correctionPipeline)) ?? text
            }
            group.addTask {
                let timeout = UInt64(Self.softTimeoutSeconds(for: settings.onlineProvider) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: timeout)
                return text
            }

            let result = await group.next() ?? text
            group.cancelAll()
            return result
        }
    }

    func testConnection(settings: AppSettings, correctionPipeline: TextCorrectionPipeline) async throws -> String {
        let messages = [
            RequestBody.Message(role: "system", content: "你是在线配置测试助手。请严格只返回“在线配置成功”。"),
            RequestBody.Message(role: "user", content: "请只回复：在线配置成功")
        ]

        return try await sendRequest(
            messages: messages,
            settings: settings,
            correctionPipeline: correctionPipeline
        )
    }

    private func requestOptimizedText(_ text: String, settings: AppSettings, correctionPipeline: TextCorrectionPipeline) async throws -> String {
        guard settings.onlineOptimizationEnabled else { return text }

        let phrases = correctionPipeline.customPhrases.joined(separator: "、")
        let ruleHints = correctionPipeline.replacementRules
            .map { "\($0.source)->\($0.target)" }
            .joined(separator: "；")

        let systemPrompt = renderTemplate(
            settings.optimizerSystemPromptTemplate,
            replacements: [
                "EXTRA_PROMPT": settings.extraPrompt,
                "PRIORITY_PHRASES": phrases,
                "RULE_HINTS": ruleHints,
                "TEXT": text
            ]
        )

        let userPrompt = renderTemplate(
            settings.optimizerUserPromptTemplate,
            replacements: [
                "EXTRA_PROMPT": settings.extraPrompt,
                "PRIORITY_PHRASES": phrases,
                "RULE_HINTS": ruleHints,
                "TEXT": text
            ]
        )

        return try await sendRequest(
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            settings: settings,
            correctionPipeline: correctionPipeline
        )
    }

    private func sendRequest(
        messages: [RequestBody.Message],
        settings: AppSettings,
        correctionPipeline: TextCorrectionPipeline
    ) async throws -> String {
        _ = correctionPipeline

        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = settings.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = settings.onlineProvider.normalizedEndpoint(from: settings.apiEndpoint)

        guard settings.onlineOptimizationEnabled else {
            throw OptimizationError.invalidConfiguration("在线纠错当前未启用。")
        }
        guard !apiKey.isEmpty else {
            throw OptimizationError.invalidConfiguration("API Key 为空。")
        }
        guard !modelName.isEmpty else {
            throw OptimizationError.invalidConfiguration("模型名为空。")
        }
        guard !endpoint.isEmpty else {
            throw OptimizationError.invalidConfiguration("接口地址为空。")
        }
        guard let url = URL(string: endpoint) else {
            throw OptimizationError.invalidEndpoint
        }

        let body = RequestBody(
            model: modelName,
            messages: messages,
            temperature: requestTemperature(for: settings.onlineProvider, endpoint: endpoint),
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = settings.requestTimeoutSeconds
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw serverError(from: data, response: response)
        }

        let decoded: ResponseBody
        do {
            decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw OptimizationError.invalidResponse
        }

        guard let optimized = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !optimized.isEmpty else {
            throw OptimizationError.emptyResponse
        }

        return optimized
    }

    private func renderTemplate(_ template: String, replacements: [String: String]) -> String {
        var output = template
        for (key, value) in replacements {
            output = output.replacingOccurrences(of: "{{\(key)}}", with: value)
        }

        let lines = output.components(separatedBy: .newlines)
        let compacted = lines.reduce(into: [String]()) { partialResult, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if partialResult.last?.isEmpty == true { return }
                partialResult.append("")
            } else {
                partialResult.append(line)
            }
        }

        return compacted.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestTemperature(for provider: OnlineProvider, endpoint: String) -> Double? {
        if provider == .volcengineCodingPlan || endpoint.contains("/api/coding/v3/") {
            return nil
        }

        return 0.1
    }

    private static func softTimeoutSeconds(for provider: OnlineProvider) -> Double {
        switch provider {
        case .volcengineCodingPlan:
            return 1.4
        case .openAICompatible:
            return 1.8
        }
    }

    private func serverError(from data: Data, response: URLResponse) -> OptimizationError {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.isEmpty {
                return .server(statusCode: statusCode, message: message)
            }
            if let message = object["message"] as? String, !message.isEmpty {
                return .server(statusCode: statusCode, message: message)
            }
        }

        if let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return .server(statusCode: statusCode, message: raw)
        }

        return .server(statusCode: statusCode, message: "未返回可读错误信息。")
    }
}
