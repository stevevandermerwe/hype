# Hype for Mac — native Swift/SwiftUI rewrite

A new, sibling app to the existing Qt/C++ Hype (`../../src`), which keeps serving
Linux/Omarchy unchanged. This one targets macOS only, reimplemented in
Swift/SwiftUI from the documented file format (`../../src/format.md`) rather than
by wrapping the C++ core. Lives at `apps/mac/` as a Swift package so it builds
and tests headlessly (`swift build`, `swift test`) without needing an `.xcodeproj`;
proper `.app` bundling (icon, Info.plist, code signing) is Phase 2 work, alongside
export.

Behavior is intentionally re-derived from `format.md` and the Qt app's observed
behavior, not transliterated line-by-line from the C++. Expect small differences;
where one is found and matters, prefer matching the Qt app unless SwiftUI makes a
different choice clearly better, and note the difference in a comment.

## Phases

1. **Core editing** (this session): open/save a presentation, `HypeCore`'s
   `Deck`/`parseDeck`/`scalar`/`setScalar`/media-directive parsing, a slide
   sidebar, a Markdown source editor for the selected slide, a live SwiftUI
   preview (headline/bullets/quote/code/table, image fit/span/left/right,
   background, overlay), bundled themes (tokyo-night, nord, gruvbox), undo/redo,
   add/duplicate/delete/move slides. No AI, no export, no CLI yet.
2. **Present + export**: a presenter window (arrow keys, Space for video),
   PDF export (vector text, matching the Qt renderer's layout), and HTML export
   (self-contained, matching `src/html.cpp`'s viewer). PowerPoint export is a
   stretch goal for this phase, not a requirement.
3. **AI generation**: the start page (Open / Wing it / Plan it / Mind map),
   whole-deck generation against an OpenAI-compatible endpoint, and per-slide
   Ask AI (text / diagram / image), matching `src/generator.cpp`'s behavior and
   prompt templates (`src/prompt.md`, `src/mindmap.md`, `src/slide-*.md`).
4. **CLI**: a `hype` command-line tool (as a second SPM executable target)
   mirroring `new`/`check`/`slides`/`render`/`export`/`generate`/`revise`/`themes`,
   sharing `HypeCore` with the app.

## Format notes carried over from the Qt app (see `format.md` for the full spec)

- One Markdown file; slides split on a line holding only `---` with blank lines
  on either side; a `---` inside a fenced code block does not split.
  Front matter is a `---`-delimited YAML-ish block at the very top.
- `scalar`/`setScalar`: a `key: value` line, JSON-decoded when quoted with `"`,
  literal (with `''`→`'`) when single-quoted, else the raw trimmed text.
- Each slide holds at most one `![directives](file)` media reference. Known
  directives: `fit`, `span`, `left`, `right`, `background=#rrggbb|blur|auto|white|black`,
  `overlay=0..1`, `loop`, `muted`, `autoplay=false`, `poster=file`. A bare
  `left`/`right` places the image in that half of the slide and moves the text to
  the other half (no darkening/blur there); anything else in the brackets that
  doesn't parse as a directive is alt text.
- Themes: `theme:` in front matter names a bundled palette; `color_*` front
  matter keys override individual colors and take precedence.
