# Hype Help

Hype turns a single Markdown file into slide presentations, PDF, and HTML.

## The editor

The main window has three views, switched from the toolbar or the **View** menu:

- **Slide** — live preview of the selected slide above its Markdown source.
- **Source** — the whole Markdown file in a text editor, including YAML front matter.
- **Light Table** — every slide as a grid for rearranging the deck.

## A presentation on disk

A talk is one folder:

```text
my-talk/
  presentation.md
  images/      photos, diagrams, animated GIF/WebP, SVG
  videos/      mp4, m4v, mov, webm, mkv
```

Media is referenced by filename only: `![](city.jpg)` reads `images/city.jpg` and `![](demo.mp4)` reads `videos/demo.mp4`.

## Front matter

The block at the very top configures the deck:

```markdown
---
title: "My talk"
theme: tokyo-night
font: "JetBrains Mono"
show_page_number: true
---
```

Use the **Front Matter…** toolbar button for a visual editor, or **View → Source** to edit the YAML directly. See **Help → YAML Front Matter** for every supported key.

## Slides

Separate slides with a line holding only `---`, with a blank line on either side:

```markdown
# A big idea

---

# Keep it simple

- Write in Markdown
- Tell your story
```

A `---` inside a fenced code block does **not** split a slide.

## Images and video

Each slide takes one image or video. Options go inside the brackets:

| Markdown | Result |
| --- | --- |
| `![](diagram.png)` | Show the whole image |
| `![span](photo.jpg)` | Fill the slide, cropping as needed |
| `![right](diagram.png)` | Image in the right half, text in the left |
| `![fit](photo.jpg)` | Show the whole image with text overlaid |
| `![fit background=blur](portrait.jpg)` | Fill the background with a blurred copy |
| `![overlay=0.5](photo.jpg)` | Darken the picture behind text |
| `![loop muted](demo.mp4)` | Loop a video without sound |
| `![poster=still.png](demo.mp4)` | Show an image until the video plays |

## Export and present

Use **File → Export as PDF** or **Export as HTML**, or run `hype export` from the terminal. Start the presenter from the toolbar or **Present → Present**.

## AI features

- **Generate with AI** builds a whole deck from a description.
- **Ask AI About This Slide** rewrites or improves the current slide.
- **Generate a Picture** asks an image model for a slide background.

Set your endpoint and model in **Hype → Settings** or with the `HYPE_AI_KEY`, `HYPE_AI_ENDPOINT`, and `HYPE_AI_MODEL` environment variables.

## More help

- **Help → Markdown Format** — the full slide format
- **Help → YAML Front Matter** — every front-matter key
- **Help → Keyboard Shortcuts** — shortcuts for editing and presenting
