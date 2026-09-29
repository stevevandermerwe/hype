# YAML Front Matter

The block between the first two `---` lines at the top of the file is YAML front matter. It configures the whole presentation.

```markdown
---
title: "My talk"
theme: tokyo-night
font: "JetBrains Mono"
show_page_number: true
tags:
  - swift
  - macos
---
```

Hype uses the full YAML syntax, so lists, booleans, numbers, and nested objects are allowed.

## Common keys

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `title` | string | file name | Presentation title |
| `theme` | string | `tokyo-night` | Theme name; run `hype themes` to list them |
| `font` | string | system font | Font family or PostScript name |
| `text_scale` | number | `1` | Scale all text (`0.5`–`2`) |

## Page numbers and title

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `show_page_number` | bool | `false` | Show slide page numbers |
| `title_position` | string | `top` | `top` or `bottom` |
| `show_title` | bool | `false` | Show the presentation title |
| `title_color` | string | theme color | `#rrggbb` hex color for the title |
| `title_style` | string | | `bold`, `italic`, `uppercase`, `underline`, or a space-separated list |
| `page_number_color` | string | theme color | `#rrggbb` hex color for page numbers |
| `page_number_position` | string | | `top` or `bottom` |

## Color overrides

Any theme color can be overridden with a `#rrggbb` value:

| Key | Typical use |
| --- | --- |
| `color_background` | Slide background |
| `color_foreground` | Main text |
| `color_accent` | Accent elements |
| `color_green` | Success/positive |
| `color_red` | Errors/negative |
| `color_yellow` | Warnings/highlights |
| `color_magenta` | Secondary accent |
| `color_cyan` | Tertiary accent |
| `color_dark_foreground` | Text on dark backgrounds |

## Custom keys

Any YAML key you add is preserved by Hype. You can use the source editor to add custom metadata such as `author`, `date`, `tags`, or `category`.

## Source view

Open **View → Source** (`⌘2`) to edit the front matter directly as YAML.
