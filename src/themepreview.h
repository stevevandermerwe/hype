#pragma once
#include <QImage>
#include <QSize>
#include <QVariantMap>

// Paint a miniature sample slide in the given palette: a headline, a few body
// lines, and a code block whose tokens pick up the theme's syntax colors. Used
// to preview themes before applying them.
QImage renderThemePreview(const QVariantMap &palette, const QSize &size);
