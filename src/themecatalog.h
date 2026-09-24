#pragma once
#include <QMap>
#include <QString>
#include <QStringList>
#include <QVariantMap>

// Discovers installed Omarchy themes and resolves their palettes. Extracted from
// Deck so theme discovery stays a small, self-contained concern. The catalog is
// read-only after construction: deck settings are snapshotted into the Markdown
// front matter, not kept here.
class ThemeCatalog {
  public:
    void discover();
    QStringList names() const;
    bool contains(const QString &name) const;
    // Just the color_* values a theme's colors.toml declares, with no defaults.
    QVariantMap overrides(const QString &name) const;
    // The resolved palette: defaults overlaid with the theme's colors.toml.
    QVariantMap paletteForTheme(const QString &name) const;

  private:
    QMap<QString, QString> m_themes; // name -> colors.toml path
};
