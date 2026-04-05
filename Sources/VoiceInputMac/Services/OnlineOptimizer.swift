import Foundation

struct OnlineOptimizer {
    struct QuotaInfo: Equatable, Sendable {
        let remainingRequests: Int?
        let limitRequests: Int?
        let remainingTokens: Int?
        let limitTokens: Int?

        var summary: String? {
            if let remaining = remainingRequests, let limit = limitRequests {
                return "剩余额度：\(remaining)/\(limit) 次请求"
            }
            if let remaining = remainingTokens, let limit = limitTokens {
                return "剩余额度：\(remaining)/\(limit) tokens"
            }
            if let remaining = remainingRequests {
                return "剩余请求：\(remaining) 次"
            }
            return nil
        }

        static func from(_ httpResponse: HTTPURLResponse) -> QuotaInfo? {
            let headers = httpResponse.allHeaderFields
            let remainReq = (headers["x-ratelimit-remaining-requests"] as? String).flatMap(Int.init)
            let limitReq = (headers["x-ratelimit-limit-requests"] as? String).flatMap(Int.init)
            let remainTok = (headers["x-ratelimit-remaining-tokens"] as? String).flatMap(Int.init)
            let limitTok = (headers["x-ratelimit-limit-tokens"] as? String).flatMap(Int.init)
            if remainReq != nil || limitReq != nil || remainTok != nil || limitTok != nil {
                return QuotaInfo(remainingRequests: remainReq, limitRequests: limitReq, remainingTokens: remainTok, limitTokens: limitTok)
            }
            return nil
        }
    }

    enum AttemptResult {
        case notEnabled(String)
        case optimized(String, quota: QuotaInfo?, elapsed: TimeInterval)
        case fallbackToLocal(String, reason: String)
    }

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

    struct GeminiRequestBody: Encodable {
        struct Part: Encodable {
            let text: String
        }

        struct Content: Encodable {
            let role: String
            let parts: [Part]
        }

        struct SystemInstruction: Encodable {
            let parts: [Part]
        }

        struct GenerationConfig: Encodable {
            let temperature: Double?
        }

        let systemInstruction: SystemInstruction?
        let contents: [Content]
        let generationConfig: GenerationConfig?
    }

    struct GeminiResponseBody: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }

                let parts: [Part]?
            }

            let content: Content?
        }

        let candidates: [Candidate]?
    }

    func optimize(_ text: String, settings: AppSettings, correctionPipeline: TextCorrectionPipeline) async throws -> String {
        switch await optimizeWithDiagnostics(text, settings: settings, correctionPipeline: correctionPipeline) {
        case let .notEnabled(result), let .optimized(result, _, _), let .fallbackToLocal(result, _):
            return result
        }
    }

    func optimizeWithDiagnostics(_ text: String, settings: AppSettings, correctionPipeline: TextCorrectionPipeline) async -> AttemptResult {
        guard settings.onlineOptimizationEnabled else { return .notEnabled(text) }

        let start = Date()
        return await withTaskGroup(of: AttemptResult.self) { group in
            group.addTask {
                do {
                    let (optimized, quota) = try await requestOptimizedText(text, settings: settings, correctionPipeline: correctionPipeline)
                    return .optimized(optimized, quota: quota, elapsed: Date().timeIntervalSince(start))
                } catch {
                    return .fallbackToLocal(text, reason: error.localizedDescription)
                }
            }
            group.addTask {
                let timeout = UInt64(Self.softTimeoutSeconds(for: settings) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: timeout)
                return .fallbackToLocal(text, reason: "在线纠错超时，已回退到本地结果。")
            }

            let result = await group.next() ?? .fallbackToLocal(text, reason: "在线纠错未返回结果，已回退到本地结果。")
            group.cancelAll()
            return result
        }
    }

    func testConnection(settings: AppSettings, correctionPipeline: TextCorrectionPipeline) async throws -> (String, QuotaInfo?) {
        let messages = [
            RequestBody.Message(role: "system", content: "你是在线配置测试助手。请严格只返回“在线配置成功”。"),
            RequestBody.Message(role: "user", content: "请只回复：在线配置成功")
        ]

        return try await sendRequest(
            messages: messages,
            settings: settings,
            correctionPipeline: correctionPipeline,
            skipEnabledCheck: true
        )
    }

    private func requestOptimizedText(_ text: String, settings: AppSettings, correctionPipeline: TextCorrectionPipeline) async throws -> (String, QuotaInfo?) {
        guard settings.onlineOptimizationEnabled else { return (text, nil) }

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
        correctionPipeline: TextCorrectionPipeline,
        skipEnabledCheck: Bool = false
    ) async throws -> (String, QuotaInfo?) {
        _ = correctionPipeline

        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = settings.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = settings.onlineProvider.normalizedEndpoint(from: settings.apiEndpoint)

        if !skipEnabledCheck {
            guard settings.onlineOptimizationEnabled else {
                throw OptimizationError.invalidConfiguration("在线纠错当前未启用。")
            }
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
        request.timeoutInterval = settings.requestTimeoutSeconds

        if settings.onlineProvider == .googleGemini {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let currentPath = components?.path ?? ""
            components?.path = normalizedGeminiPath(currentPath: currentPath, modelName: modelName)
            let queryItems = components?.queryItems ?? []
            components?.queryItems = queryItems + [URLQueryItem(name: "key", value: apiKey)]

            guard let geminiURL = components?.url else {
                throw OptimizationError.invalidEndpoint
            }

            request.url = geminiURL
            request.httpBody = try JSONEncoder().encode(geminiBody(from: messages))
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw serverError(from: data, response: response)
        }

        let quota = QuotaInfo.from(httpResponse)

        if settings.onlineProvider == .googleGemini {
            let decoded: GeminiResponseBody
            do {
                decoded = try JSONDecoder().decode(GeminiResponseBody.self, from: data)
            } catch {
                throw OptimizationError.invalidResponse
            }

            let optimized = decoded.candidates?
                .first?
                .content?
                .parts?
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let optimized, !optimized.isEmpty else {
                throw OptimizationError.emptyResponse
            }

            return (optimized, quota)
        } else {
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

            return (optimized, quota)
        }
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

    private func geminiBody(from messages: [RequestBody.Message]) -> GeminiRequestBody {
        let systemMessage = messages.first(where: { $0.role == "system" })
        let userContents = messages
            .filter { $0.role != "system" }
            .map { message in
                GeminiRequestBody.Content(
                    role: message.role == "assistant" ? "model" : "user",
                    parts: [.init(text: message.content)]
                )
            }

        return GeminiRequestBody(
            systemInstruction: systemMessage.map {
                .init(parts: [.init(text: $0.content)])
            },
            contents: userContents,
            generationConfig: .init(temperature: 0.1)
        )
    }

    private func normalizedGeminiPath(currentPath: String, modelName: String) -> String {
        if currentPath.contains(":generateContent") {
            return currentPath
        }

        let trimmed = currentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty || trimmed == "v1beta" {
            return "/v1beta/models/\(modelName):generateContent"
        }

        if trimmed.hasSuffix("/models") {
            return "/\(trimmed)/\(modelName):generateContent"
        }

        if trimmed.contains("/models/") {
            return "/\(trimmed)"
        }

        return "/v1beta/models/\(modelName):generateContent"
    }

    private static func softTimeoutSeconds(for settings: AppSettings) -> Double {
        let configured = max(1.0, settings.onlineSoftTimeoutSeconds)
        let requestTimeout = max(1.0, settings.requestTimeoutSeconds)
        return min(configured, requestTimeout)
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
