#include "themecatalog.h"
#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QStandardPaths>

void ThemeCatalog::discover() {
    m_themes.clear();
    const QString omarchy = qEnvironmentVariable("OMARCHY_PATH");
    QStringList roots;
    if (!omarchy.isEmpty())
        roots << omarchy + "/themes";
    else
        roots << QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/omarchy/themes";
    roots << QDir::homePath() + "/omarchy/themes";
    roots << QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/omarchy/themes";
    for (auto &r : roots)
        for (auto &name : QDir(r).entryList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            const QString path = r + "/" + name + "/colors.toml";
            if (QFile::exists(path))
                m_themes[name] = path;
        }
}

QStringList ThemeCatalog::names() const { return m_themes.keys(); }
bool ThemeCatalog::contains(const QString &name) const { return m_themes.contains(name); }

QVariantMap ThemeCatalog::overrides(const QString &name) const {
    QVariantMap colors;
    QFile f(m_themes.value(name));
    if (f.open(QIODevice::ReadOnly)) {
        static const QRegularExpression re("^([a-z_]+)\\s*=\\s*\"(#[0-9a-fA-F]{6})\"",
                                          QRegularExpression::MultilineOption);
        auto matches = re.globalMatch(QString::fromUtf8(f.readAll()));
        while (matches.hasNext()) {
            auto m = matches.next();
            colors[m.captured(1)] = m.captured(2);
        }
    }
    return colors;
}

QVariantMap ThemeCatalog::paletteForTheme(const QString &name) const {
    QVariantMap colors{
        {"background", "#1a1b26"}, {"foreground", "#c0caf5"}, {"accent", "#7aa2f7"},
        {"green", "#9ece6a"},      {"red", "#f7768e"},        {"yellow", "#e0af68"},
        {"magenta", "#bb9af7"},    {"cyan", "#7dcfff"},       {"dark_foreground", "#787c99"}};
    const QVariantMap theme = overrides(name);
    for (auto it = theme.cbegin(); it != theme.cend(); ++it)
        colors[it.key()] = it.value();
    return colors;
}
