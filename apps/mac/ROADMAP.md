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
2. **Present + export** (done): a presenter window (arrow keys, Space, Home/End
   navigate; Escape closes), PDF export (real vector text via
   `ImageRenderer`+`CGContext`, one page per slide at 960×540pt), and HTML
   export (self-contained, base64 PNGs, matching `src/html.cpp`'s documented
   viewer: arrows/Space/Page Up/Down/Home/End navigate, F fullscreen, G grid).
   All three verified against the running app, not just compiled — see
   `SlideExport.swift` and `PresenterView.swift`. Known gaps: the presenter
   window doesn't reliably auto-enter fullscreen on open (manual fullscreen
   still works); no video playback in Present; PowerPoint export is not
   implemented (a stretch goal, not a requirement for this phase).
3. **AI generation** (done): the start page (Open / Wing it / Plan it / Mind
   map, with a Recent list), whole-deck generation against an OpenAI-compatible
   endpoint, and per-slide Ask AI (text / diagram / image), matching
   `src/generator.cpp`'s behavior. The bundled prompt templates
   (`Sources/HypeCore/Resources/*.md`) are copied verbatim from
   `src/{prompt,mindmap,slide-text,slide-diagram,format}.md` — keep them in
   sync by hand if either side changes. The API key comes from `HYPE_AI_KEY`,
   the configured environment variable, or the macOS Keychain (via the
   `Security` framework directly, not shelling out). 21 unit tests
   (`GeneratorTests.swift`) exercise the whole pipeline — request building, key
   resolution, reply parsing, path-safety, file writing, theme application,
   warnings — against a mocked `URLProtocol`, mirroring the Qt app's
   `test_generate.py`. The UI (start page, Generate sheet, Ask AI sheet) was
   verified visually and its layout/controls exercised live; a full live
   network round-trip through the GUI against a local fake endpoint was
   attempted but not completed — AppleScript-driven text-field targeting in
   this environment proved too unreliable to trust against a real desktop
   session (it also nearly interacted with an unrelated app), so that step was
   abandoned in favor of the code-level test coverage above. Known gap: unlike
   the Qt app, `DeckModel.chooseTheme` does not bake `color_*` overrides into
   the file — bundled themes are a fixed set resolved by name at render time,
   not discovered from disk paths, so there is no portability need for baking
   them; a deck generated here still looks right in this app, but its `theme:`
   name alone won't carry the exact palette if opened somewhere without that
   theme built in.
4. **CLI** (done): a `hype` executable target (`Sources/HypeCLI`) with
   `new`/`check`/`slides`/`render`/`export`/`generate`/`revise`/`themes`/`help`,
   mirroring `src/cli.cpp`. Manual argument parsing (`Args.swift`), no external
   dependency. Every command was run for real and its output inspected — not
   just compiled: `new`/`check` (including a deliberately broken deck: missing
   image with the right line number, an empty slide warning, correct exit
   code), `slides`, `themes`, `render` (single slide and a whole deck, real
   PNGs at a requested width), `export` (a real multi-page PDF, a real
   self-contained HTML file), and `generate`/`revise` against a local fake
   HTTP endpoint (no real API key). This surfaced and fixed a real parser bug:
   `Args` only recognized `--flag`, not the single-dash `-o` the documented
   command syntax actually uses. Rendering/export needed extracting the
   SwiftUI-based renderer out of `HypeApp` into a new shared library,
   `HypeRender` (`SlidePreviewView`, `drawSlide`, `exportPDF`/`exportHTML`/
   `renderSlidePNG`), which `HypeApp` now also depends on — so the app and the
   CLI render every slide identically by construction, not by convention.
   Known gaps versus the Qt CLI: no PowerPoint export; `check` does not warn
   when text would render below a readable size (would need threading a
   measurement path through `HypeRender` not built for this phase); no
   `--template`/font-related options, since this port has no external-template
   or font-management story yet.

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
  matter keys override individual colors and take precedence. The Mac app
  bundles 13 (`hype themes` lists them): Omarchy's tokyo-night, nord, and
  gruvbox, plus catppuccin, rose-pine, everforest, kanagawa, dracula,
  midnight, and the light catppuccin-latte, rose-pine-dawn, solarized-light,
  and paper, from each theme's upstream palette.
- Slide content (`SlideBlocks.swift`): a slide's text is parsed into blocks —
  headline, body lines, fenced code, tables — that the renderer lays out.
  Tables are real grids (header row, per-column alignment from `:--`/`:-:`/`--:`,
  wide cells wrap while narrow columns stay whole). Code is highlighted by a
  built-in scanner (`SyntaxHighlight.swift`, 18 languages plus aliases, no
  dependency) on a panel that follows the theme. Known gap: highlighting is a
  scanner, not a parser, so unusual syntax can be coloured oddly.
- Text fitting (`TextFitting.swift`, tested in `HypeRenderTests`): text is
  sized as large as it can be with every line kept whole. The headline is
  sized on its own (shrinking to stay on one line) so it doesn't drag the body
  down. Lines wrap only when keeping them whole would leave body text below
  36 units of a 1080-tall slide, or wrapping makes it at least 1.3× bigger
  while it's under 52. A slide that still can't reach 36 is "too full": it gets
  a badge in the sidebar and light table, a banner with a "Shorten with AI"
  button, a status-bar count, and a `hype check` warning
  (`measureSlideText`). Known gap: wrapped bullet lines don't hang-indent.
- Editor assists (`MarkdownEdit.swift`, `ImageLayout.swift`, `FormatBar.swift`):
  a button bar and Format menu (⌘B/⌘I/⌘U, ⌥⌘1–6, ⇧⌘M) that write the syntax:
  heading (Hype has one level, `# `), bold, italic, underline, inline code,
  bullet and numbered lists, quote, code block (with a language list), table,
  hidden speaker note, insert picture or video (copied into `images/`/`videos/`),
  and picture layout (left/right, fit/span, backdrops, darken, loop/mute).
  Styles toggle and skip a line's `- `/`1. `/`# `/`> ` marker; Return continues
  a list or quote. The editor is an `NSTextView` (`TextEditor` can't expose its
  selection on macOS 14). Known gaps: no clear-formatting button, the light
  table has no assists, and sidebar titles show raw `**` from styled headlines.
- `text_scale:` (Mac-only extension, 0.5–2, default 1) scales every slide's
  text: above 1 it raises the size fitted text may grow to, below 1 it
  shrinks the fitted size. The Qt app ignores the key, so such a deck renders
  at its normal fitted size there.
- `font:` names an installed font (family or PostScript name); slides use it,
  falling back to the system font when it isn't installed (`hype check` warns).
  Code stays monospaced. Toolbar font picker; `hype new --font`.
- Custom themes (`ThemeStore.swift`): one JSON file per theme in
  `~/Library/Application Support/Hype/Themes` (override with `HYPE_THEMES_DIR`),
  made in a theme editor (colour wells, live preview, "start from"). Choosing a
  theme clears stale `color_*` keys; a custom theme's colours are also written
  into the deck so it looks right on a Mac without the theme. `hype themes` and
  `hype new --theme` know them.

## Later additions (beyond the four phases)

- **AI:** whole-deck rewrite and speaker-note drafting (both validate the reply
  and apply as one undo; a wrong slide count or an invented picture is refused
  or repaired), picture generation from a popover in the format bar, an AI menu,
  and a fix so Stop really cancels requests. Each window states where the deck
  is sent before sending it.
- **Editing:** find and replace across the deck (regex, whole word, match case;
  picture filenames are never matched), twelve slide templates (title, quote,
  big number, two columns, …), and dropping pictures/videos onto the preview,
  a sidebar thumbnail, or the editor (extra files become new slides).
- **Safety:** recovery snapshots of unsaved edits (`Recovery.swift`, in
  `~/Library/Application Support/Hype/Recovery`, override `HYPE_RECOVERY_DIR`)
  offered on the start page after a crash; timestamped backups beside the file
  (`.hype-backups`, newest ten) before a save overwrites it; and a
  Save / Don't Save / Cancel prompt before New, Open, or Quit would discard edits.
- **Packaging:** `bin/package` builds a universal, hardened-runtime `Hype.app`
  and `Hype-<version>.dmg` in `dist/` (version from `VERSION`), signing with
  `CODESIGN_IDENTITY` and notarizing with `NOTARY_PROFILE` (or Apple ID
  variables) when set; the `hype` tool ships inside the app and
  `bin/install-cli` puts it on your PATH. Unverified here: real Developer ID
  signing and notarization (they need your Apple credentials).
