import Foundation

/// The deck-wide AI requests: rewrite every slide, or draft speaker notes.
/// Like the per-slide edits in `Generator`, these only return a result; the
/// caller decides whether to apply it (as one undoable edit).
extension Generator {
    /// Applies `instruction` ("make this more concise", "translate to Spanish")
    /// to every slide. The reply is validated (see `parseDeckRewriteReply`), so
    /// a malformed answer fails and changes nothing.
    public func rewriteDeck(instruction: String, slides: [String]) async -> Result<DeckRewriteResult, GeneratorError> {
        let request = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            status = "Say what to change in the deck."
            return .failure(GeneratorError(status))
        }
        guard !slides.isEmpty else {
            status = "The deck has no slides."
            return .failure(GeneratorError(status))
        }
        guard let system = deckRewriteTemplate() else {
            status = "Could not read the prompt template."
            return .failure(GeneratorError(status))
        }
        busy = true
        status = "Rewriting \(slides.count) slide\(slides.count == 1 ? "" : "s")…"
        defer { busy = false }
        let body = buildChatRequestBody(model: config.model, system: system,
                                        user: deckRewriteRequest(instruction: request, slides: slides))
        switch await post(endpoint: config.endpoint, model: config.model, body: body) {
        case .failure(let error):
            status = error.message
            return .failure(error)
        case .success(let data):
            let parsed = parseChatReply(data)
            if !parsed.error.isEmpty { status = parsed.error; return .failure(GeneratorError(parsed.error)) }
            let result = parseDeckRewriteReply(parsed.content, original: slides)
            if !result.error.isEmpty { status = result.error; return .failure(GeneratorError(result.error)) }
            status = "Rewrote \(result.changed) of \(slides.count) slide\(slides.count == 1 ? "" : "s")"
            return .success(result)
        }
    }

    /// Drafts speaker notes for the slides at `targets` (0-based). The whole deck
    /// is sent for context; `guidance` is optional style direction.
    public func suggestNotes(slides: [String], targets: [Int], guidance: String) async -> Result<SpeakerNotesResult, GeneratorError> {
        let wanted = Array(Set(targets.filter { slides.indices.contains($0) })).sorted()
        guard !wanted.isEmpty else {
            status = "No slides need notes."
            return .failure(GeneratorError(status))
        }
        guard let system = speakerNotesTemplate() else {
            status = "Could not read the prompt template."
            return .failure(GeneratorError(status))
        }
        busy = true
        status = "Writing notes for \(wanted.count) slide\(wanted.count == 1 ? "" : "s")…"
        defer { busy = false }
        let body = buildChatRequestBody(model: config.model, system: system,
                                        user: speakerNotesRequest(slides: slides, targets: wanted, guidance: guidance))
        switch await post(endpoint: config.endpoint, model: config.model, body: body) {
        case .failure(let error):
            status = error.message
            return .failure(error)
        case .success(let data):
            let parsed = parseChatReply(data)
            if !parsed.error.isEmpty { status = parsed.error; return .failure(GeneratorError(parsed.error)) }
            let result = parseSpeakerNotesReply(parsed.content, wanted: wanted)
            if !result.error.isEmpty { status = result.error; return .failure(GeneratorError(result.error)) }
            status = "Wrote notes for \(result.notes.count) slide\(result.notes.count == 1 ? "" : "s")"
            return .success(result)
        }
    }

    /// Draws a picture for the selected slide from `description`, saves it in the
    /// deck's `images/` folder, and adds it to the slide as one undoable edit.
    /// Returns a message for the status bar. The deck must be saved (pictures
    /// need a folder), and the selection must not change while the model works.
    public func addPicture(_ description: String, to deck: DeckModel) async -> Result<String, GeneratorError> {
        let index = deck.selected
        switch await editSlide(instruction: description, kind: "image", slide: deck.slideText(at: index),
                               outline: deck.slideOutline(), index: index, baseDir: deck.baseDir) {
        case .failure(let error):
            return .failure(error)
        case .success(let outcome):
            guard deck.selected == index else {
                return .failure(GeneratorError("The selected slide changed while waiting, so nothing was applied."))
            }
            deck.editSlide(outcome.slide)
            let warnings = outcome.warnings.count
            return .success("Added a picture" + (warnings == 0 ? "" : "; \(warnings) warning\(warnings > 1 ? "s" : ""), see the slide"))
        }
    }
}
