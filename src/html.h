#pragma once
#include <QString>

// Build a self-contained HTML slideshow from a rendered directory: reads
// slides.json and embeds each slide PNG as a base64 data URI, so the result
// is a single shareable file with keyboard, fullscreen, and overview controls.
bool writeHtml(const QString &directory, const QString &path, QString *error);
