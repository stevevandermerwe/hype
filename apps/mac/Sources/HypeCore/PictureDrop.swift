import Foundation

/// The files in `urls` that Hype can show as a slide's picture or video.
public func mediaFiles(in urls: [URL]) -> [URL] {
    urls.filter {
        let ext = $0.pathExtension.lowercased()
        return imageExtensions.contains(ext) || videoExtensions.contains(ext)
    }
}

/// Handles pictures and videos dropped onto slide `index`: each is copied into
/// the deck's `images/` or `videos/` folder (never overwriting), the first is
/// set as that slide's picture (swapping one already there, keeping its layout
/// options), and any others each become a new slide after it. All of it is one
/// undoable edit. Files that aren't pictures or videos are ignored; if none are,
/// or the deck is unsaved, nothing changes and the error says why.
///
/// The result is a message for the status bar.
@MainActor
public func dropPictures(_ urls: [URL], onto index: Int, in deck: DeckModel) -> Result<String, MediaImportError> {
    let media = mediaFiles(in: urls)
    guard !media.isEmpty else {
        return .failure(.unsupported(urls.first?.lastPathComponent ?? "These files"))
    }
    guard !deck.baseDir.isEmpty else { return .failure(.needsSavedDeck) }
    var slides = deck.slideTexts
    guard slides.indices.contains(index) else { return .failure(.copyFailed("There is no slide \(index + 1).")) }

    var names: [String] = []
    for url in media {
        do {
            names.append(try importMedia(from: url, into: deck.baseDir))
        } catch let error as MediaImportError {
            return .failure(error)
        } catch {
            return .failure(.copyFailed(error.localizedDescription))
        }
    }
    slides[index] = setImageFile(names[0], in: slides[index]).trimmingCharacters(in: .whitespacesAndNewlines)
    let extras = names.dropFirst().map { "![](\(pictureReference($0)))" }
    slides.insert(contentsOf: extras, at: index + 1)
    deck.replaceSlides(slides)
    deck.select(index)

    var message = "Added \(names[0])"
    if !extras.isEmpty { message += " to slide \(index + 1) and \(extras.count) more as new slide\(extras.count == 1 ? "" : "s")" }
    return .success(message)
}

/// A filename as written inside `![](…)`: angle brackets if it has spaces or parentheses.
func pictureReference(_ file: String) -> String {
    file.contains(where: { $0 == " " || $0 == "(" || $0 == ")" }) ? "<\(file)>" : file
}
