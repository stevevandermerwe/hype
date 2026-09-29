import Foundation

/// A plain-text failure message — `Result`'s failure type must conform to
/// `Error`, and a bare `String` does not.
public struct GeneratorError: Error, CustomStringConvertible, Sendable {
    public var message: String
    public var description: String { message }
    public init(_ message: String) { self.message = message }
}

/// AI generation: a prompt (and, for one slide, an instruction) plus a
/// template go to any OpenAI-compatible endpoint; the reply becomes a new
/// presentation folder or a revised slide. Matches the Qt app's `Generator`
/// (`generator.h`/`.cpp`), using Swift concurrency instead of Qt's
/// signal/slot + `QNetworkAccessManager`.
@MainActor
public final class Generator: ObservableObject {
    @Published public var config: AIConfig
    @Published public private(set) var busy = false
    @Published public var status = ""

    private let session: URLSession
    private var currentTask: Task<Void, Never>?

    public init(config: AIConfig = AIConfigStore.load(), session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func saveSettings() { AIConfigStore.save(config) }
    public var keySource: String? { resolveAPIKey(config)?.source }
    public var outputRoot: String { config.outputRoot.isEmpty ? defaultOutputRoot() : config.outputRoot }

    /// Cancels the in-flight request, if any.
    public func cancel() {
        currentTask?.cancel()
    }

    private static let requestTimeout: TimeInterval = 300
    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    /// Validates the endpoint/model/key, posts `body`, and returns the raw
    /// reply bytes. Matches `Generator::begin` (`generator.cpp`).
    private func post(endpoint: String, model: String, body: Data) async -> Result<Data, GeneratorError> {
        guard let url = URL(string: endpoint), let scheme = url.scheme, ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            return .failure(GeneratorError("The endpoint must be an http(s) URL, such as \(AIConfig.defaultEndpoint)"))
        }
        guard !model.isEmpty else { return .failure(GeneratorError("Choose a model.")) }
        let isLocal = Generator.localHosts.contains(host) || host.hasSuffix(".localhost")
        let resolved = resolveAPIKey(config)
        if resolved == nil, !isLocal {
            let variable = config.keyEnvironmentVariable.isEmpty ? "HYPE_AI_KEY" : config.keyEnvironmentVariable
            return .failure(GeneratorError("No API key. Set \(variable) in the environment, or save one to the Keychain."))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let resolved { request.setValue("Bearer \(resolved.key)", forHTTPHeaderField: "Authorization") }
        request.setValue("Hype", forHTTPHeaderField: "X-Title")
        request.httpBody = body
        request.timeoutInterval = Generator.requestTimeout
        do {
            let (data, response) = try await session.data(for: request)
            let http = (response as? HTTPURLResponse)?.statusCode ?? 200
            if http >= 400 {
                let parsed = parseChatReply(data)
                let message = parsed.error.isEmpty ? "HTTP \(http)" : "HTTP \(http): \(parsed.error)"
                return .failure(GeneratorError(message))
            }
            return .success(data)
        } catch let error as URLError where error.code == .cancelled {
            return .failure(GeneratorError("Cancelled"))
        } catch {
            return .failure(GeneratorError(error.localizedDescription))
        }
    }

    /// Writes a whole new presentation from a prompt. Matches
    /// `Generator::generate`/`finishPresentation` (`generator.cpp`).
    public func generate(prompt: String, theme: String?, directory: String?, mode: String?) async -> Result<WrittenPresentation, GeneratorError> {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let message = mode == "mindmap" ? "Paste your mind map first." : "Describe the presentation you want."
            status = message
            return .failure(GeneratorError(message))
        }
        guard let system = promptTemplate(mode: mode) else {
            status = "Could not read the prompt template."
            return .failure(GeneratorError(status))
        }
        busy = true
        status = "Generating…"
        defer { busy = false }
        let body = buildChatRequestBody(model: config.model, system: system,
                                        user: prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        switch await post(endpoint: config.endpoint, model: config.model, body: body) {
        case .failure(let error):
            status = error.message
            return .failure(error)
        case .success(let data):
            let parsed = parseChatReply(data)
            if !parsed.error.isEmpty { status = parsed.error; return .failure(GeneratorError(parsed.error)) }
            let files = parseGeneratedFiles(parsed.content)
            if !files.error.isEmpty { status = files.error; return .failure(GeneratorError(files.error)) }
            let written = writePresentation(files, directory: directory, outputRoot: outputRoot, theme: theme)
            if !written.error.isEmpty { status = written.error; return .failure(GeneratorError(written.error)) }
            status = "Created \(written.path)"
            return .success(written)
        }
    }

    /// Changes one slide's text, draws a diagram for it, or adds a generated
    /// picture. Matches `Generator::editSlide`/`finishSlide` (`generator.cpp`).
    public func editSlide(instruction: String, kind: String, slide: String, outline: String, index: Int,
                          baseDir: String) async -> Result<SlideEditOutcome, GeneratorError> {
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Say what to change on this slide."
            return .failure(GeneratorError(status))
        }
        guard ["text", "diagram", "image"].contains(kind) else {
            return .failure(GeneratorError("Unknown kind of change: \(kind)"))
        }
        if kind != "text", baseDir.isEmpty {
            status = "Save the presentation first (Cmd+S), so the picture has a folder to go in."
            return .failure(GeneratorError(status))
        }
        busy = true
        defer { busy = false }
        if kind == "image" {
            status = "Drawing…"
            let endpoint = config.imageEndpoint.isEmpty ? config.endpoint : config.imageEndpoint
            guard let url = URL(string: endpoint) else { return .failure(GeneratorError("The image endpoint is not a valid URL.")) }
            let body = buildImageRequestBody(endpoint: url, model: config.imageModel,
                                             prompt: imagePrompt(instruction: instruction, slide: slide))
            switch await post(endpoint: endpoint, model: config.imageModel, body: body) {
            case .failure(let error): status = error.message; return .failure(error)
            case .success(let data):
                let image = parseImageReply(data)
                if !image.error.isEmpty { status = image.error; return .failure(GeneratorError(image.error)) }
                let added = addPictureToSlide(baseDir: baseDir, slide: slide, image: image, hint: instruction)
                if !added.error.isEmpty { status = added.error; return .failure(GeneratorError(added.error)) }
                status = "Added a picture"
                return .success(SlideEditOutcome(slide: added.slide, warnings: slideProblems(added.slide, base: baseDir),
                                                 summary: "Added a picture"))
            }
        }
        status = "Rewriting…"
        guard let system = slideTemplate(kind: kind) else { return .failure(GeneratorError("Could not read the slide template.")) }
        let body = buildChatRequestBody(model: config.model, system: system,
                                        user: slideRequest(instruction: instruction, slide: slide, outline: outline, index: index))
        switch await post(endpoint: config.endpoint, model: config.model, body: body) {
        case .failure(let error): status = error.message; return .failure(error)
        case .success(let data):
            let parsed = parseChatReply(data)
            if !parsed.error.isEmpty { status = parsed.error; return .failure(GeneratorError(parsed.error)) }
            let reply = parseSlideReply(parsed.content, withImages: kind == "diagram")
            if !reply.error.isEmpty { status = reply.error; return .failure(GeneratorError(reply.error)) }
            var slideText = reply.slide
            if !reply.images.isEmpty {
                let written = writeSlidePictures(baseDir: baseDir, reply: reply)
                if !written.error.isEmpty { status = written.error; return .failure(GeneratorError(written.error)) }
                slideText = written.slide
            }
            let summary = reply.images.isEmpty ? "Rewrote the slide"
                : "Rewrote the slide and drew \(reply.images.count) picture\(reply.images.count > 1 ? "s" : "")"
            status = summary
            return .success(SlideEditOutcome(slide: slideText,
                                             warnings: baseDir.isEmpty ? [] : slideProblems(slideText, base: baseDir),
                                             summary: summary))
        }
    }
}
