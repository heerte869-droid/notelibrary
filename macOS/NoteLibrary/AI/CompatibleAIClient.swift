import Foundation
import OpenAI

/// Shared OpenAI-compatible transport. Provider/model names stay data, not parser branches.
/// SDK revision and upstream licenses are recorded in THIRD_PARTY_NOTICES.md.
@MainActor
struct CompatibleAIClient {
    let session: URLSession
    var inspectBody: ((Data) -> Void)? = nil
    var inspectResponse: ((Data) -> Void)? = nil

    private func client(baseURL: String, key: String, timeout: TimeInterval, middleware: CompatibilityEnvelope) throws -> OpenAI {
        let address = try APIEndpoint.normalized(baseURL)
        guard let url = URL(string: address), let host = url.host else { throw AppFailure(message: "接口根地址无效。") }
        // URL.host exposes the unbracketed IPv6 literal; URLComponents.host (used by
        // the SDK) needs brackets or its URL becomes invalid and loses the base path.
        let transportHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return OpenAI(configuration: .init(token: key.isEmpty ? nil : key, host: transportHost,
            port: url.port ?? (url.scheme == "http" ? 80 : 443), scheme: url.scheme ?? "https",
            basePath: url.path, timeoutInterval: timeout, parsingOptions: .relaxed),
            session: session, middlewares: [middleware])
    }

    func chat(baseURL: String, key: String, body: [String: Any], onText: @escaping (String) -> Void) async throws -> String {
        let middleware = CompatibilityEnvelope()
        middleware.inspectBody = inspectBody
        defer { inspectResponse?(middleware.responseData) }
        let sdk = try client(baseURL: baseURL, key: key, timeout: 240, middleware: middleware)
        let messages: [ChatQuery.ChatCompletionMessageParam] = (body["messages"] as? [[String: Any]] ?? []).compactMap { message in
            if message["role"] as? String == "system", let text = message["content"] as? String { return .system(.init(content: .textContent(text))) }
            guard message["role"] as? String == "user" else { return nil }
            if let text = message["content"] as? String { return .user(.init(content: .string(text))) }
            let content = message["content"] as? [[String: Any]] ?? []
            if content.allSatisfy({ $0["type"] as? String == "text" }) {
                return .user(.init(content: .string(content.compactMap { $0["text"] as? String }.joined(separator: "\n"))))
            }
            let parts: [ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart] = (message["content"] as? [[String: Any]] ?? []).compactMap { part in
                if let text = part["text"] as? String { return .text(.init(text: text)) }
                if let image = part["image_url"] as? [String: Any], let url = image["url"] as? String { return .image(.init(imageUrl: .init(url: url, detail: nil))) }
                return nil
            }
            return .user(.init(content: .contentParts(parts)))
        }
        defer { withExtendedLifetime(sdk) {} }
        // Keep schema dictionaries intact: the app uses JSON Schema union/null types.
        // The middleware only supplies the requested schema, never rewrites model output.
        middleware.responseFormat = body["response_format"] as? [String: Any]
        middleware.completionBudget = body["max_completion_tokens"] as? Int
        var query = ChatQuery(messages: messages, model: body["model"] as? String ?? "", stream: true)
        query.maxTokens = body["max_tokens"] as? Int
        var output = "", finished = false
        do {
            for try await chunk in sdk.chatsStream(query: query) {
                try Task.checkCancellation()
                guard let choice = chunk.choices.first else { continue } // usage-only chunk
                if choice.delta.refusal != nil { throw AppFailure(message: "模型未能完成这次请求，原资料未改动。") }
                if let reason = choice.finishReason {
                    switch reason {
                    case .stop: finished = true
                    default: throw AppFailure(message: "模型未完整返回正文，原资料未改动。请检查输出上限或模型的工具调用设置。")
                    }
                }
                output += choice.delta.content ?? ""
                let visible = AIService.answerText(output)
                if !visible.isEmpty { onText(visible) }
            }
            try Task.checkCancellation()
            guard finished || middleware.receivedCompleteResponse else { throw AppFailure(message: "回复连接提前结束，原资料未改动。请重试。") }
            let visible = AIService.answerText(output)
            guard !visible.isEmpty else { throw AppFailure(message: "模型没有返回可用正文，请检查模型与输出设置。") }
            return visible
        } catch { throw Self.readable(error, key: key, middleware: middleware) }
    }

    func image(baseURL: String, key: String, model: String, prompt: String, format: String) async throws -> ImagesResult.Image {
        let imageProtocol = ImageGenerationProtocol(rawValue: format) ?? .openai
        let middleware = CompatibilityEnvelope(imageEnvelope: true, imageProtocol: imageProtocol, imageEndpoint: try imageProtocol.endpoint(baseURL))
        let sdk = try client(baseURL: baseURL, key: key, timeout: 600, middleware: middleware)
        do {
            let result = try await sdk.images(query: ImagesQuery(prompt: prompt, model: model, n: format == "siliconflow" ? nil : 1))
            try Task.checkCancellation()
            guard let image = result.data.first(where: { $0.url?.isEmpty == false || $0.b64Json?.isEmpty == false }) else { throw AppFailure(message: "服务未返回图像，请检查生图模型与接口。") }
            return image
        } catch { throw Self.readable(error, key: key, middleware: middleware) }
    }

    private static func readable(_ error: Error, key: String, middleware: CompatibilityEnvelope) -> Error {
        if Task.isCancelled || error is CancellationError { return CancellationError() }
        if let transport = error as? URLError { return transport }
        if let failure = error as? AppFailure { return failure }
        if case let OpenAIError.statusError(_, status) = error {
            return ProviderRequestFailure(data: middleware.responseData, status: status, key: key)
        }
        if let status = middleware.statusCode, !(200..<300).contains(status) {
            return ProviderRequestFailure(data: middleware.responseData, status: status, key: key)
        }
        if let body = (try? JSONSerialization.jsonObject(with: middleware.responseData)) as? [String: Any],
           let failure = ProviderRequestFailure.embeddedError(body),
           let data = try? JSONSerialization.data(withJSONObject: ["error": failure]) {
            return AIService.serviceError(data, status: 400, key: key)
        }
        if error is DecodingError { return AppFailure(message: "服务返回的数据与所选接口不匹配，请检查接口类型。") }
        var detail = error.localizedDescription
        if !key.isEmpty { detail = detail.replacingOccurrences(of: key, with: "[已隐藏]") }
        return AppFailure(message: String(detail.prefix(500)))
    }
}

/// Protocol-level compatibility only: some endpoints ignore stream=true; SiliconFlow
/// names its image array `images`. The upstream SDK still owns requests, SSE parsing,
/// typed responses and cancellation. No request is repeated to detect a response format.
final class CompatibilityEnvelope: OpenAIMiddleware, @unchecked Sendable {
    private let lock = NSLock()
    private let imageEnvelope: Bool
    private let imageProtocol: ImageGenerationProtocol
    private let imageEndpoint: URL?
    private var pending = Data()
    private var mode: Bool? // true: JSON response; false: SSE
    private var complete = false
    private var streamTail = Data()
    private var rawResponse = Data()
    private var httpStatus: Int?
    var responseFormat: [String: Any]?
    var completionBudget: Int?
    var inspectBody: ((Data) -> Void)?
    var receivedCompleteResponse: Bool { lock.withLock { complete } }
    var responseData: Data { lock.withLock { rawResponse } }
    var statusCode: Int? { lock.withLock { httpStatus } }
    init(imageEnvelope: Bool = false, imageProtocol: ImageGenerationProtocol = .openai, imageEndpoint: URL? = nil) {
        self.imageEnvelope = imageEnvelope; self.imageProtocol = imageProtocol; self.imageEndpoint = imageEndpoint
    }

    func intercept(request: URLRequest) -> URLRequest {
        guard let data = request.httpBody,
              var body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return request }
        var request = request
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        if let responseFormat { body["response_format"] = responseFormat }
        if let completionBudget { body.removeValue(forKey: "max_tokens"); body["max_completion_tokens"] = completionBudget }
        if let imageEndpoint { request.url = imageEndpoint }
        if imageEnvelope { body = imageProtocol.request(body) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        if let payload = request.httpBody { inspectBody?(payload) }
        return request
    }
    func interceptStreamingData(request: URLRequest?, _ data: Data) -> Data {
        lock.withLock {
            if rawResponse.count < 16_384 { rawResponse.append(data.prefix(16_384 - rawResponse.count)) }
            let markerBytes = streamTail + data
            let marker = String(decoding: markerBytes, as: UTF8.self)
            if marker.range(of: #"(?m)^data: *\[DONE\]\r?$"#, options: .regularExpression) != nil { complete = true }
            streamTail = Data(markerBytes.suffix(64))
            if mode == false { return data }
            guard mode != true || !complete else { return Data() }
            pending.append(data)
            if mode == nil, let first = pending.first(where: { ![9, 10, 13, 32].contains($0) }) { mode = first == 123 }
            if mode == false { let result = pending; pending.removeAll(); return result }
            guard pending.count < 8_000_000 else {
                pending.removeAll(); complete = true
                return Data(#"{"error":{"type":"invalid_response","message":"服务响应超过大小限制。"}}"#.utf8)
            }
            guard var object = (try? JSONSerialization.jsonObject(with: pending)) as? [String: Any] else { return Data() }
            if let failure = ProviderRequestFailure.embeddedError(object) {
                return (try? JSONSerialization.data(withJSONObject: ["error": failure])) ?? pending
            }
            if object["error"] != nil { return pending } // let SDK decode the real error
            guard var choices = object["choices"] as? [[String: Any]] else { return pending }
            for index in choices.indices {
                if let message = choices[index].removeValue(forKey: "message") { choices[index]["delta"] = message }
            }
            object["choices"] = choices
            guard let converted = try? JSONSerialization.data(withJSONObject: object) else { return Data() }
            complete = true; pending.removeAll()
            return Data("data: ".utf8) + converted + Data("\n\n".utf8)
        }
    }
    func intercept(response: URLResponse?, request: URLRequest, data: Data?) -> (response: URLResponse?, data: Data?) {
        lock.withLock {
            httpStatus = (response as? HTTPURLResponse)?.statusCode
            rawResponse = Data((data ?? Data()).prefix(16_384))
            guard imageEnvelope, httpStatus.map({ (200..<300).contains($0) }) == true,
                  let data, var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], object["error"] == nil else { return (response, data) }
            object = imageProtocol.response(object)
            if object["data"] == nil, let images = object["images"] { object["data"] = images }
            if object["created"] == nil { object["created"] = 0 }
            return (response, (try? JSONSerialization.data(withJSONObject: object)) ?? data)
        }
    }
}

/// Only an explicit, pre-generation parameter rejection permits compatibility negotiation.
/// Authentication, quotas, bad prompts, disconnects and partially generated replies never do.
struct ProviderRequestFailure: LocalizedError {
    let status: Int
    let detail: String
    let errorDescription: String?

    @MainActor init(data: Data, status: Int, key: String) {
        self.status = status
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let error = object["error"] as? [String: Any] ?? object
        let raw = [error["param"], error["code"], error["type"], error["message"], error["detail"]].compactMap { $0.map { String(describing: $0) } }.joined(separator: " ")
        detail = (key.isEmpty ? raw : raw.replacingOccurrences(of: key, with: "[hidden]")).lowercased()
        errorDescription = AIService.serviceError(data, status: status, key: key).message
    }

    func rejects(_ parameters: [String]) -> Bool {
        guard [400, 422].contains(status), parameters.contains(where: detail.contains) else { return false }
        if ["not supported", "unsupported", "unknown parameter", "unrecognized", "not permitted", "not allowed", "不支持", "未知参数", "不允许"].contains(where: detail.contains) { return true }
        // A parameter/type being unavailable is distinct from the service or model
        // being unavailable. Do not turn a general outage into a format retry.
        return parameters.contains { parameter in
            detail.range(of: NSRegularExpression.escapedPattern(for: parameter) + #"(?: type| mode)? (?:is |are )?(?:currently )?(?:unavailable|not available)"#, options: .regularExpression) != nil
        }
    }

    static func embeddedError(_ body: [String: Any]) -> [String: Any]? {
        if let error = body["error"] as? [String: Any] { return error }
        if let images = body["data"] as? [[String: Any]], !images.contains(where: { $0["url"] != nil || $0["b64_json"] != nil }),
           let error = images.compactMap({ $0["error"] as? [String: Any] }).first { return error }
        if let base = body["base_resp"] as? [String: Any], let code = base["status_code"] as? Int, code != 0 {
            return ["type": "provider_error", "code": String(code), "message": base["status_msg"] as? String ?? "服务请求失败（\(code)）"]
        }
        if let code = body["code"], let message = body["message"] as? String,
           !["0", "200", "OK"].contains(String(describing: code)) {
            return ["type": "provider_error", "code": String(describing: code), "message": message]
        }
        return nil
    }
}

/// Protocol mapping follows LiteLLM's DashScope image adapter (MIT); see Vendor/ProviderReferences.
/// Model IDs pass through unchanged. URL derivation always preserves the configured host/region.
enum ImageGenerationProtocol: String, CaseIterable {
    case openai, siliconflow, dashscope, gemini, glm, doubao, minimax, openrouter

    var title: String {
        switch self {
        case .openai: return "OpenAI Images 兼容"
        case .siliconflow: return "硅基流动 Images"
        case .dashscope: return "阿里云 DashScope 生图"
        case .gemini: return "Gemini Images"
        case .glm: return "智谱 Images"
        case .doubao: return "豆包 Images"
        case .minimax: return "MiniMax 生图"
        case .openrouter: return "OpenRouter Images"
        }
    }

    static func resolved(profile: APIProfile, modelID: String) -> Self {
        if let format = profile.catalog.first(where: { $0.id == modelID })?.imageFormat,
           let explicit = Self(rawValue: format) { return explicit }
        let host = URL(string: profile.baseURL)?.host?.lowercased() ?? ""
        // A preset name is not authority to rewrite a custom gateway's wire protocol.
        switch host {
        case "api.siliconflow.cn", "api.siliconflow.com": return .siliconflow
        case "generativelanguage.googleapis.com": return .gemini
        case "open.bigmodel.cn", "api.z.ai": return .glm
        case "ark.cn-beijing.volces.com", "ark.ap-southeast.bytepluses.com": return .doubao
        case "api.minimax.io", "api.minimax.chat": return .minimax
        case "openrouter.ai": return .openrouter
        default: break
        }
        let officialHosts: Set<String> = ["dashscope.aliyuncs.com", "dashscope-intl.aliyuncs.com", "dashscope-us.aliyuncs.com"]
        if officialHosts.contains(host) || host.hasSuffix(".maas.aliyuncs.com") { return .dashscope }
        return .openai
    }

    func endpoint(_ baseURL: String) throws -> URL? {
        if self == .minimax { return try APIEndpoint.url(baseURL, path: "/image_generation") }
        if self == .openrouter { return try APIEndpoint.url(baseURL, path: "/images") }
        guard self == .dashscope else { return nil }
        guard var components = URLComponents(string: try APIEndpoint.normalized(baseURL)) else { throw AppFailure(message: "生图地址无效。") }
        var prefix = components.path
        if prefix.hasSuffix("/compatible-mode/v1") { prefix.removeLast("/compatible-mode/v1".count) }
        else if prefix.hasSuffix("/api/v1") { prefix.removeLast("/api/v1".count) }
        components.path = prefix + "/api/v1/services/aigc/multimodal-generation/generation"
        guard let url = components.url else { throw AppFailure(message: "生图地址无效。") }
        return url
    }

    func request(_ body: [String: Any]) -> [String: Any] {
        var body = body
        switch self {
        case .gemini: body["response_format"] = "b64_json"
        case .siliconflow:
            body.removeValue(forKey: "n")
            body["image_size"] = body.removeValue(forKey: "size") ?? "1024x1024"
        case .glm, .doubao: body.removeValue(forKey: "n")
        case .minimax: body["response_format"] = "base64"
        default: break
        }
        guard self == .dashscope else { return body }
        var parameters: [String: Any] = [:]
        if let n = body["n"] { parameters["n"] = n }
        if let size = body["size"] as? String { parameters["size"] = size.replacingOccurrences(of: "x", with: "*") }
        return ["model": body["model"] ?? "", "input": ["messages": [["role": "user", "content": [["text": body["prompt"] ?? ""]]]]], "parameters": parameters]
    }

    func response(_ body: [String: Any]) -> [String: Any] {
        if let failure = ProviderRequestFailure.embeddedError(body) { return ["error": failure] }
        if self == .minimax {
            let data = body["data"] as? [String: Any] ?? [:]
            let images = (data["image_base64"] as? [String] ?? []).map { ["b64_json": $0] }
                + (data["image_urls"] as? [String] ?? []).map { ["url": $0] }
            return ["created": 0, "data": images]
        }
        guard self == .dashscope else { return body }
        // A protocol-level failure can be delivered with HTTP 200; never treat it as an image.
        if let code = body["code"] as? String, body["output"] == nil {
            return ["error": ["type": code, "code": code, "message": body["message"] as? String ?? code]]
        }
        let output = body["output"] as? [String: Any] ?? [:]
        let choices = output["choices"] as? [[String: Any]] ?? []
        let images: [[String: Any]] = choices.flatMap { choice in
            let message = choice["message"] as? [String: Any] ?? [:]
            let content = message["content"] as? [[String: Any]] ?? []
            return content.compactMap { item in (item["image"] as? String).map { ["url": $0] } }
        }
        return ["created": 0, "data": images]
    }
}
