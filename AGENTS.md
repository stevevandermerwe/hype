# AGENTS.md

Hype is a native desktop app (Qt 6 / C++ / QML, C++17) that turns a single Markdown
file into slide presentations, PDF, PowerPoint, and HTML. It is part of the Omarchy
ecosystem (Linux-first, macOS supported). Version 0.4.1. The presentation format
itself is documented in `src/format.md` and printed at runtime by `hype help format`.

## Build, test, run

All scripts live in `bin/` (shell scripts, no build system beyond qmake).

```sh
./bin/build                        # qmake + make into build/hype; default qmake6,
                                   # override with QMAKE=qmake (needed for official Qt).
./bin/test                         # builds and runs the Qt Test suite (tests/tests.cpp)
                                   # headless in build/tests/hype-tests.
python3 -m unittest discover -s tests -p 'test_*.py'   # Python suite; needs build/hype.
./bin/dev                          # build then launch the editor (locks on build dir).
./bin/install                      # makepkg -fsi (Arch/Omarchy packaging).
./bin/install-dev                  # register a "Hype (Development)" launcher entry.
./bin/prepare-trials               # convert private Keynote/PPTX archives into trials/.
```

- The Python tests execute the real `build/hype` binary, so run `./bin/build` first.
- The Python tests need `ffmpeg`, `ffprobe`, and `source-highlight` on `PATH`
  (`tests/test_export.py` symlinks them into a fake tools dir to isolate the app).
  `tests/test_trials.py` imports `tools/*.py` directly. Some tests need `PyYAML`.
- CI (`.github/workflows/ci.yml`) mirrors this: Qt 6.9.2 via jurplel, `ffmpeg
  source-highlight libwebp zlib`, `QMAKE=qmake ./bin/build`; a second job runs the
  LibreOffice round-trip export test with `HYPE_OFFICE_TESTS=1`.
- `build/hype` must not be run from the repo root's `build/` dir by the Python tests
  for theme isolation; they set `OMARCHY_PATH`/`XDG_CONFIG_HOME`/`HOME` to temp dirs.

Verbosity: CLI commands take `--json` for structured output, exit 0 on success and 1
on failure, and write errors to stderr. `hype help <command>` lists options and
`hype help format` prints the whole slide format.

## Code organization

- `src/deck.{h,cpp}` — the core model. `Deck` is a `QAbstractListModel` whose rows
  are slides; it owns `AssetStore`, `ThemeCatalog`, `Recovery`, a `QFileSystemWatcher`
  for external edits, and the undo/redo stacks. `parseDeck()` splits the Markdown
  source into slides, code-fence aware, on lines holding only `---` with blank lines
  either side. Front matter is kept separately in the deck header.
  Undo/redo store full-source `State` snapshots (source + selection), not diffs.
- `src/renderer.cpp` — renders slides to `QImage` at slide size (export renders at
  4K, 3840×2160). `src/syntax.cpp` shells out to `source-highlight` for code fences.
- `src/cli.cpp` — headless commands (`new`, `check`, `slides`, `render`, `export`,
  `generate`, `revise`, `themes`, `skill`, `open`, `help`) with no display needed.
- `src/pptx.cpp`, `src/html.cpp`, `src/exporter.cpp`, `src/animationexport.cpp` —
  export backends. PPTX renders slides as 4K bitmap images (not editable shapes),
  converts animated WebP/GIF and non-H.264 videos to MP4 via ffmpeg.
- `src/images.cpp`, `src/assetstore.cpp` — media handling: paste, background
  compression (lossless PNG/WebP, 4K cap), size computation.
- `src/themecatalog.cpp` — theme discovery from `$OMARCHY_PATH/themes/*/colors.toml`,
  falling back to `~/.local/share/omarchy/themes`, `~/omarchy/themes`, and
  `~/.config/omarchy/themes`. `src/themepreview.cpp` renders thumbnails; the
  `image://theme/<name>` provider in `src/main.cpp` serves them to QML.
- `src/recovery.cpp` — autosave snapshots in `~/.local/state/hype/recovery/` (under
  `$XDG_STATE_HOME`), plus `.hype-backups/` beside the presentation.
- `src/generator.cpp` — AI generation: sends a prompt + template to any
  OpenAI-compatible endpoint (`/v1/chat/completions`), reads the key from
  `HYPE_AI_KEY` or a named variable (macOS Keychain for GUI use), parses replies
  in the `=== FILE: path ===` layout into a new folder with SVG images.
- `src/main.cpp` — entry point; decides GUI vs CLI, sets up theme previews, desktop
  font via the settings portal, and QML. macOS uses a `QApplication` subclass to
  catch `QFileOpenEvent` (Finder double-click) and `isatty(STDIN)` to tell a
  double-clicked app from a CLI run.
- `src/*.qml`, `resources.qrc` — the editor UI (`Main.qml`, `StartPage.qml`,
  `GenerateDialog.qml`, `SlideAssistDialog.qml`, `Markdown.js`, `AppIcon.qml`). Deck methods are `Q_INVOKABLE`
  for QML. A plain launch (no file, no unsaved draft) shows `StartPage.qml`, driven by
  the `showStartPage` context property set in `main.cpp`; tests load `Main.qml`
  without it, so it must stay optional (`typeof showStartPage`).
- `tools/` — development-only fixtures (`import_trial.py`, `refine_trials.py`,
  `trial_io.py`, `requirements-trials.txt`) for converting real Keynote/PPTX decks
  into Markdown trials. Not a general-purpose importer. Trial output lives under
  `trials/`, which is gitignored; `TRIALS.md` documents the Rails World decks.
- `tests/` — `tests.cpp` (Qt Test, covers deck parsing, undo, media directives,
  export failure protection) plus the Python suite. `tests/fixtures/` holds animated
  GIF/WebP files.
- `pkgbuild/` — Arch PKGBUILD, desktop file, and macOS bundle assets
  (`macos/Info.plist`, `macos/entitlements.plist`, `macos/make-icns.sh`). Mac bundle
  uses `QMAKE_TARGET_BUNDLE_PREFIX = org.omarchy` (stable reverse-DNS id, independent
  of the build machine's Xcode templates).

## Key gotchas

- **`CONFIG += exceptions_off`** in `hype.pro`: the code never throws or catches.
  No `try/catch`, no exception-based error handling; errors flow through return
  values and `Deck::status()`.
- **clangd will report hundreds of "file not found" errors** for Qt headers — the
  repo has no compile_commands.json and clangd lacks Qt include paths. These are
  environmental noise, not real errors. Build with `./bin/build` and judge.
- **`exceptions_off` + `ltcg`**: the binary is built with link-time optimization;
  keep new files in the qmake `SOURCES`/`HEADERS` lists (both `hype.pro` and
  `tests/tests.pro` list sources explicitly — new files must be added to both).
- **Markdown dialect is custom**: `*asterisks*` = italic, `_underscores_` =
  underline, `**double**` = bold. Ordinary line breaks stay visible on the slide;
  `<!-- comments -->` are hidden speaker notes. A `---` inside a code fence must not
  split the slide (covered by tests).
- **Export runs in a separate worker process**: `Deck::startExport` spawns a fresh
  copy of the hype binary with `--export-snapshot <file> --<format> <path>`; the
  worker reports JSON progress lines on stdout. The snapshot isolates the running
  editor from export. `HYPE_DESKTOP_FILE` names the desktop entry (used by
  `bin/dev` as `hype-dev`).
- **Headless behavior is load-bearing**: commands and exports set
  `QT_QPA_PLATFORM=offscreen` automatically, and the gtk3 platform theme is forced
  off (`QT_QPA_PLATFORMTHEME=generic`) to avoid a GTK use-after-free on theme
  change. Tests assert commands fail gracefully with no display at all.
- **macOS**: `main.cpp` appends Homebrew paths (`/opt/homebrew/bin`,
  `/usr/local/bin`) to `PATH` because Finder launches omit them; `bin/build` and
  `bin/test` expose `/opt/homebrew` lib/include dirs since libwebp is outside the
  default linker path (`LIBRARY_PATH`/`CPATH`). Linux file dialogs use freedesktop
  portals (`src/filedialog.cpp`); macOS compiles in `QT += widgets` and uses
  `QFileDialog`.
- **Version is set in two places**: `VERSION = 0.4.1` in `hype.pro` and a hardcoded
  `app.setApplicationVersion("0.4.1")` in `src/main.cpp`. Bump both.
- **Slide editing is string-preserving**: operations rewrite exact source text;
  tests verify byte-for-byte preservation on move/duplicate and that a failed
  export leaves an existing output file intact. Keep this contract.
- **Media by filename only**: `![](diagram.png)` resolves to `images/`, video to
  `videos/`. Layout/directives go in the brackets: `fit`, `span`, `left`, `right`,
  `background=#rrggbb|blur|auto`, `overlay=0..1`, `loop`, `muted`,
  `autoplay=false`, `poster=file.png`. Each slide holds exactly one image/video.
  (To literally use "left"/"right" as alt text, write `alt="left"`.)
- External file edits: the editor watches the presentation file and merges external
  changes live, but never overwrites its own unsaved edits (protected in tests).

## Style

`.clang-format` is LLVM-based: 4-space indent, 100-column limit, `#pragma once`,
access-modifier indentation per LLVM (e.g. `public:` at column 2). C++17. Follow the
existing comment style: file-scope comments explain *why* (build flags, portal
fallbacks) — keep that. Python in `tools/` is plain stdlib (only PyYAML as a test
dependency); no third-party imports.