#include "deck.h"
#include "animationexport.h"
#include "exporter.h"
#include "markdown.h"
#include "filedialog.h"
#include "html.h"
#include "images.h"
#include "pptx.h"
#include "renderer.h"
#include <QGuiApplication>
#include <QCache>
#include <QClipboard>
#include <QCryptographicHash>
#include <QDataStream>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QFontDatabase>
#include <QFutureWatcher>
#include <QImageReader>
#include <QImageWriter>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QMimeData>
#include <QPainter>
#include <QPdfWriter>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QScopeGuard>
#include <QSettings>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QThreadPool>
#include <QtConcurrentRun>
#include <atomic>
#include <cerrno>
#include <climits>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <memory>

ParsedDeck parseDeck(const QString &source) {
    ParsedDeck result;
    int contentStart = source.startsWith(QChar(0xfeff)) ? 1 : 0;
    auto lineAt = [&](int offset, int *next) {
        int end = source.indexOf('\n', offset);
        *next = end < 0 ? source.size() : end + 1;
        QString line = source.mid(offset, (end < 0 ? source.size() : end) - offset);
        if (line.endsWith('\r'))
            line.chop(1);
        return line;
    };
    int next = 0;
    if (lineAt(contentStart, &next) == "---") {
        int offset = next;
        bool closed = false;
        while (offset < source.size()) {
            QString line = lineAt(offset, &next);
            if (line == "---") {
                contentStart = next;
                closed = true;
                break;
            }
            offset = next;
        }
        if (!closed) {
            result.error = "Front matter needs a closing ---";
            result.errorOffset = contentStart;
            result.slides.append({source, 0, int(source.size())});
            return result;
        }
    }
    result.header = source.left(contentStart);
    // A top-level --- inside a fenced code block is code, not a slide break.
    // Fence scanning starts after front matter, exactly as the original did.
    const auto fences = markdownFences(source, contentStart);
    int start = contentStart, pos = start;
    while (pos < source.size()) {
        QString line = lineAt(pos, &next);
        if (line == "---" && !insideFence(fences, pos)) {
            result.slides.append({source.mid(start, pos - start), start, pos});
            start = next;
        }
        pos = next;
    }
    result.slides.append({source.mid(start), start, int(source.size())});
    if (fences.unclosedOffset >= 0 && result.error.isEmpty()) {
        result.error = "Unclosed code fence";
        result.errorOffset = fences.unclosedOffset;
    }
    return result;
}
QString scalar(const QString &header, const QString &key, const QString &fallback) {
    QRegularExpression re("^" + QRegularExpression::escape(key) + ":\\s*([^\\r\\n]*)$",
                          QRegularExpression::MultilineOption);
    auto m = re.match(header);
    if (!m.hasMatch())
        return fallback;
    QString value = m.captured(1).trimmed();
    if (value.startsWith('"') && value.endsWith('"')) {
        auto doc = QJsonDocument::fromJson(("[" + value + "]").toUtf8());
        if (doc.isArray() && doc.array().size())
            return doc.array()[0].toString();
    }
    if (value.startsWith('\'') && value.endsWith('\''))
        return value.mid(1, value.size() - 2).replace("''", "'");
    return value;
}
QString setScalar(QString header, const QString &key, const QString &value) {
    QByteArray json = QJsonDocument(QJsonArray{value}).toJson(QJsonDocument::Compact);
    QString line = key + ": " + QString::fromUtf8(json.mid(1, json.size() - 2));
    QRegularExpression re("^" + QRegularExpression::escape(key) + ":[^\\r\\n]*",
                          QRegularExpression::MultilineOption);
    auto match = re.match(header);
    if (match.hasMatch())
        header.replace(match.capturedStart(), match.capturedLength(), line);
    else if (header.isEmpty())
        header = "---\n" + line + "\n---\n";
    else {
        int end = header.lastIndexOf("---");
        header.insert(end, line + "\n");
    }
    return header;
}
Deck::Deck(QObject *parent, const QString &exportProgram) : QAbstractListModel(parent),
    m_exportProgram(exportProgram.isEmpty() ? QCoreApplication::applicationFilePath() : exportProgram) {
    m_themes.discover();
    m_source = "---\ntitle: Untitled\ntheme: tokyo-night\n---\n\n# Your next idea\n";
    m_parsed = parseDeck(m_source);
    m_saved = m_source;
    // Writers may truncate, or remove and recreate, the file; read it once they settle.
    m_reloadTimer.setSingleShot(true);
    m_reloadTimer.setInterval(50);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_reloadTimer, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_reloadTimer, qOverload<>(&QTimer::start));
    connect(&m_reloadTimer, &QTimer::timeout, this, [this] {
        QFile file(m_path);
        if (m_path.isEmpty())
            return;
        if (!file.open(QIODevice::ReadOnly)) {
            m_externalChange = true;
            setStatus("Presentation changed or was removed outside Hype.");
            return;
        }
        const QString disk = QString::fromUtf8(file.readAll());
        if (disk != m_saved) {
            if (!dirty()) {
                reloadExternal(disk);
            } else {
                m_externalChange = true;
                setStatus("Changed on disk. Save a copy or reopen to reload.");
            }
        }
        watch();
    });
}
// Where the slide being viewed went in an externally edited presentation: the same text if
// it survives, else the most similar slide among those that changed around it.
static int followSlide(const QVector<Slide> &before, const QVector<Slide> &after, int selected) {
    auto text = [](const Slide &slide) { return slide.source.trimmed(); };
    const QString current = text(before[selected]);
    int first = 0, last = after.size();
    while (first < qMin(before.size(), after.size()) && text(before[first]) == text(after[first]))
        ++first;
    while (last > first && before.size() - (after.size() - last) > first &&
           text(before[before.size() - 1 - (after.size() - last)]) == text(after[last - 1]))
        --last;
    if (selected < first)
        return selected;
    if (selected >= before.size() - (after.size() - last))
        return selected + after.size() - before.size();
    // With nothing in its place, the slide that followed it takes over.
    int best = qMin(first, int(after.size()) - 1), bestScore = -1;
    for (int i = first; i < last; ++i) {
        const QString candidate = text(after[i]);
        const int limit = qMin(current.size(), candidate.size());
        int head = 0, tail = 0;
        while (head < limit && current[head] == candidate[head])
            ++head;
        while (tail < limit - head && current[current.size() - 1 - tail] == candidate[candidate.size() - 1 - tail])
            ++tail;
        const int score = candidate == current ? INT_MAX : head + tail;
        if (score > bestScore || (score == bestScore && qAbs(i - selected) < qAbs(best - selected))) {
            best = i;
            bestScore = score;
        }
    }
    return qMax(0, best);
}
// Another program, often an agent, edited the file. Stay on the slide being viewed;
// undo restores the old text.
void Deck::reloadExternal(const QString &disk) {
    const int selected = followSlide(m_parsed.slides, parseDeck(disk).slides, m_selected);
    m_saved = disk;
    m_externalChange = false;
    apply(disk, selected);
    setStatus("Reloaded external changes.");
}
int Deck::rowCount(const QModelIndex &parent) const { return parent.isValid() ? 0 : count(); }
QVariant Deck::data(const QModelIndex &index, int role) const {
    if (index.row() < 0 || index.row() >= count())
        return {};
    if (role == NumberRole)
        return index.row() + 1;
    return {};
}
QHash<int, QByteArray> Deck::roleNames() const { return {{NumberRole, "number"}}; }
QString Deck::slideSource() const { return slide(m_selected); }
static QString withoutSlidePadding(QString text) {
    // Strip boundary lines, not indentation or Markdown hard-break spaces.
    text.remove(QRegularExpression("^(?:[ \\t]*\\r?\\n)+"));
    text.remove(QRegularExpression("(?:\\r?\\n[ \\t]*)+$"));
    return text.trimmed().isEmpty() ? QString() : text;
}
QString Deck::slideText() const { return withoutSlidePadding(slideSource()); }
QString Deck::slide(int i) const {
    return i >= 0 && i < count() ? m_parsed.slides[i].source : QString();
}
QString Deck::baseDir() const {
    return m_path.isEmpty() ? QDir::currentPath() : QFileInfo(m_path).absolutePath();
}
QString Deck::title() const {
    return scalar(m_parsed.header, "title",
                  m_path.isEmpty() ? "Untitled" : QFileInfo(m_path).completeBaseName());
}
void Deck::setStatus(const QString &s) {
    m_status = s;
    if (!m_exporting && !m_exportStatus.isEmpty()) {
        m_exportStatus.clear();
        m_exportFailed = false;
        emit exportChanged();
    }
    emit statusChanged();
}
void Deck::apply(const QString &source, int selected, bool history, int anchor,
                 const ParsedDeck *structure) {
    if (source == m_source && !structure) {
        m_anchor = qBound(0, anchor < 0 ? selected : anchor, count() - 1);
        m_selected = qBound(0, selected, count() - 1);
        emit changed();
        return;
    }
    if (history) {
        m_undo.append({m_source, m_selected, m_anchor, m_parsed});
        if (m_undo.size() > 200)
            m_undo.removeFirst();
        m_redo.clear();
    }
    auto parsed = structure ? *structure : parseDeck(source);
    if (structure) {
        parsed.error.clear();
        for (const auto &slide : parsed.slides) {
            // A slide body cannot contain front matter. Prefix a plain line so
            // a leading --- is interpreted as a slide break instead.
            static thread_local QCache<QString, QString> errors(2 * 1024 * 1024);
            auto error = errors.object(slide.source);
            if (!error) {
                error = new QString(parseDeck("Slide\n" + slide.source).error);
                errors.insert(slide.source, error, qMax(1, int(slide.source.size() * 2)));
                error = errors.object(slide.source);
            }
            const QString problem = error ? *error : parseDeck("Slide\n" + slide.source).error;
            if (!problem.isEmpty()) {
                parsed.error = problem;
                break;
            }
        }
    }
    const bool reset = parsed.slides.size() != count();
    QVector<int> modified;
    if (!reset)
        for (int i = 0; i < count(); ++i)
            if (parsed.slides[i].source != m_parsed.slides[i].source)
                modified.append(i);
    if (reset)
        beginResetModel();
    if (reset)
        m_renderIds.clear();
    m_source = source;
    m_parsed = parsed;
    m_selected = qBound(0, selected, count() - 1);
    m_anchor = qBound(0, anchor < 0 ? selected : anchor, count() - 1);
    ++m_revision;
    if (reset)
        endResetModel();
    else
        for (int i : modified)
            emit dataChanged(index(i), index(i));
    emit changed();
    if (!m_parsed.error.isEmpty())
        setStatus(m_parsed.error);
}
void Deck::select(int index) {
    index = qBound(0, index, count() - 1);
    if (m_selected == index && m_anchor == index)
        return;
    m_selected = m_anchor = index;
    emit changed();
}
void Deck::extendSelection(int index) {
    index = qBound(0, index, count() - 1);
    if (m_selected == index)
        return;
    m_selected = index;
    emit changed();
}
void Deck::moveSelection(int direction) {
    if (direction < 0 && selectionFirst() > 0)
        dropSelection(selectionFirst() - 1);
    else if (direction > 0 && selectionLast() < count() - 1)
        dropSelection(selectionLast() + 2);
}
void Deck::dropSelection(int slot) {
    const int first = selectionFirst(), last = selectionLast(), length = selectionCount();
    if (slot < 0 || slot > count() || (slot >= first && slot <= last + 1))
        return;
    QStringList slides;
    for (const auto &slide : m_parsed.slides)
        slides << slide.source;
    const QStringList moving = slides.mid(first, length);
    for (int i = 0; i < length; ++i)
        slides.removeAt(first);
    const int destination = slot > last ? slot - length : slot;
    for (int i = 0; i < length; ++i)
        slides.insert(destination + i, moving[i]);
    const int offset = destination - first;
    replaceSlides(slides, m_selected + offset, m_anchor + offset);
}
void Deck::selectAt(int position) {
    for (int i = count() - 1; i >= 0; --i)
        if (position >= m_parsed.slides[i].start) {
            select(i);
            return;
        }
}
int Deck::sourcePosition() const { return m_parsed.slides.value(m_selected).start; }
void Deck::editSource(const QString &s) { apply(s, m_selected); }
void Deck::editSlide(const QString &s) {
    const auto range = m_parsed.slides.value(m_selected);
    QString body = withoutSlidePadding(s);
    if (!body.isEmpty()) {
        if (range.start > 0)
            body.prepend('\n');
        body += m_selected < count() - 1 ? "\n\n" : "\n";
    } else {
        body = "\n";
    }
    QString edited = m_source;
    edited.replace(range.start, range.end - range.start, body);
    // Qt can report the same text again when a selection or focus changes.
    // A no-op must not create an undo step or rerender the slide.
    if (edited == m_source)
        return;
    // Reparse only the edited slide. An unfinished fence must never extend this
    // editor's replacement range into the following slides on the next keystroke.
    const QString prefix = "Slide\n";
    auto fragment = parseDeck(prefix + body);
    auto parsed = m_parsed;
    const int shift = body.size() - (range.end - range.start);
    for (int i = m_selected + 1; i < parsed.slides.size(); ++i) {
        parsed.slides[i].start += shift;
        parsed.slides[i].end += shift;
    }
    parsed.slides.removeAt(m_selected);
    for (int i = 0; i < fragment.slides.size(); ++i) {
        auto slide = fragment.slides[i];
        const int start = qMax(0, slide.start - int(prefix.size()));
        const int end = slide.end - prefix.size();
        parsed.slides.insert(m_selected + i,
                             {body.mid(start, end - start), range.start + start, range.start + end});
    }
    apply(edited, m_selected, true, -1, &parsed);
}
void Deck::replaceSlides(const QStringList &slides, int selected, int anchor) {
    QString out = m_parsed.header;
    ParsedDeck parsed;
    parsed.header = m_parsed.header;
    for (int i = 0; i < slides.size(); ++i) {
        if (i)
            out += "---\n";
        const int start = out.size();
        const QString body = withoutSlidePadding(slides[i]);
        if (!body.isEmpty()) {
            if (!out.isEmpty())
                out += '\n';
            out += body + '\n';
        }
        if (i < slides.size() - 1 || body.isEmpty())
            out += '\n';
        parsed.slides.append({out.mid(start), start, int(out.size())});
    }
    apply(out, selected, true, anchor, &parsed);
}
void Deck::replaceHeader(const QString &header) {
    auto parsed = m_parsed;
    const int shift = header.size() - parsed.header.size();
    parsed.header = header;
    for (auto &slide : parsed.slides) {
        slide.start += shift;
        slide.end += shift;
    }
    apply(header + m_source.mid(m_parsed.header.size()), m_selected, true, -1, &parsed);
}
void Deck::moveSlide(int from, int to) {
    if (from < 0 || from >= count() || to < 0 || to >= count() || from == to)
        return;
    QStringList list;
    for (auto &s : m_parsed.slides)
        list << s.source;
    list.move(from, to);
    replaceSlides(list, to);
}
void Deck::addSlide() {
    QStringList list;
    for (auto &s : m_parsed.slides)
        list << s.source;
    const int next = selectionLast() + 1;
    list.insert(next, "\n\n");
    replaceSlides(list, next);
}
void Deck::duplicateSlide() {
    QStringList list;
    for (auto &s : m_parsed.slides)
        list << s.source;
    const int length = selectionCount(), next = selectionLast() + 1;
    const QStringList copies = list.mid(selectionFirst(), length);
    for (int i = 0; i < length; ++i)
        list.insert(next + i, copies[i]);
    replaceSlides(list, m_selected + length, m_anchor + length);
}
void Deck::deleteSlide() {
    QStringList list;
    for (auto &s : m_parsed.slides)
        list << s.source;
    const int first = selectionFirst();
    for (int i = 0; i < selectionCount(); ++i)
        list.removeAt(first);
    if (list.isEmpty())
        list << "\n";
    replaceSlides(list, qMin(first, int(list.size()) - 1));
}
void Deck::undo() {
    if (m_undo.isEmpty())
        return;
    auto state = m_undo.takeLast();
    m_redo.append({m_source, m_selected, m_anchor, m_parsed});
    apply(state.source, state.selected, false, state.anchor, &state.parsed);
}
void Deck::redo() {
    if (m_redo.isEmpty())
        return;
    auto state = m_redo.takeLast();
    m_undo.append({m_source, m_selected, m_anchor, m_parsed});
    apply(state.source, state.selected, false, state.anchor, &state.parsed);
}
qint64 Deck::totalBytes() const {
    const QString base = baseDir();
    if (m_totalBytes >= 0 && m_sizeSource == m_source && m_sizeBase == base &&
        m_sizeClock.isValid() && m_sizeClock.elapsed() < 1000)
        return m_totalBytes;
    QStringList paths;
    for (const auto &slide : m_parsed.slides) {
        const auto media = parseMedia(slide.source, base);
        for (const auto &path : {media.path, media.poster})
            if (!path.isEmpty())
                paths << path;
    }
    paths.removeDuplicates();
    paths.sort();
    if (paths != m_sizeFiles || !m_sizeClock.isValid() || m_sizeClock.elapsed() >= 1000) {
        m_assetBytes = 0;
        QSet<QString> files;
        for (const auto &path : paths) {
            const QFileInfo file(path);
            const auto identity = file.canonicalFilePath();
            if (file.isFile() && !files.contains(identity)) {
                files.insert(identity);
                m_assetBytes += file.size();
            }
        }
        m_sizeFiles = paths;
        m_sizeClock.start();
    }
    const qint64 bytes = m_source.toUtf8().size() + m_assetBytes;
    m_sizeSource = m_source;
    m_sizeBase = base;
    m_totalBytes = bytes;
    return bytes;
}
QString Deck::sizeLabel() const {
    return QLocale().formattedDataSize(totalBytes(), 0, QLocale::DataSizeSIFormat);
}
QStringList Deck::fontNames() const { return QFontDatabase::families(); }
QString Deck::fontName() const { return scalar(m_parsed.header, "font", "JetBrains Mono"); }
void Deck::chooseFont(const QString &family) {
    if (!fontNames().contains(family) || family == fontName())
        return;
    const QString header = setScalar(m_parsed.header, "font", family);
    replaceHeader(header);
}
QStringList Deck::themeNames() const { return m_themes.names(); }
QString Deck::themeName() const { return scalar(m_parsed.header, "theme", "tokyo-night"); }
QVariantMap Deck::palette() const {
    if (!m_paletteCache.isEmpty() && m_paletteHeader == m_parsed.header)
        return m_paletteCache;
    QVariantMap colors = paletteForTheme(themeName());
    for (const auto &key : colors.keys()) {
        QString v = scalar(m_parsed.header, "color_" + key);
        if (QColor(v).isValid())
            colors[key] = v;
    }
    colors["font"] = scalar(m_parsed.header, "font", "JetBrains Mono");
    m_paletteHeader = m_parsed.header;
    m_paletteCache = colors;
    return colors;
}
QVariantMap Deck::paletteForTheme(const QString &name) const {
    return m_themes.paletteForTheme(name);
}
QColor Deck::background() const { return QColor(palette()["background"].toString()); }
QColor Deck::foreground() const { return QColor(palette()["foreground"].toString()); }
QColor Deck::accent() const { return QColor(palette()["accent"].toString()); }
void Deck::chooseTheme(const QString &name) {
    QString header = setScalar(m_parsed.header, "theme", name);
    // Remove old palette before reading the newly selected installed theme.
    header.remove(
        QRegularExpression("^color_[a-z_]+:[^\\n]*\\n", QRegularExpression::MultilineOption));
    const auto colors = m_themes.overrides(name);
    for (auto it = colors.cbegin(); it != colors.cend(); ++it)
        header = setScalar(header, "color_" + it.key(), it.value().toString());
    replaceHeader(header);
}
QVariantMap Deck::media() const {
    const QString source = slideSource(), base = baseDir();
    if (!m_mediaCache.isEmpty() && m_mediaSource == source && m_mediaBase == base)
        return m_mediaCache;
    m_mediaSource = source;
    m_mediaBase = base;
    auto m = parseMedia(source, base);
    const bool title = !m.text.trimmed().isEmpty();
    static QCache<QString, bool> animations(1024);
    const QFileInfo file(m.path);
    const QString identity = m.path + ':' + QString::number(file.size()) + ':' +
                             QString::number(file.lastModified().toMSecsSinceEpoch());
    bool animated = false;
    if (!m.path.isEmpty() && !m.video) {
        if (const auto cached = animations.object(identity))
            animated = *cached;
        else {
            QImageReader reader(m.path);
            animated = reader.supportsAnimation() && reader.imageCount() > 1;
            animations.insert(identity, new bool(animated));
        }
    }
    m_mediaCache = {{"url", QUrl::fromLocalFile(m.path)},
                    {"video", m.video},
                    {"animated", animated},
                    {"span", m.span},
                    {"side", m.side},
                    {"loop", m.loop},
                    {"muted", m.muted},
                    {"autoplay", m.autoplay},
                    {"title", title},
                    {"rect", mediaRect(m)},
                    {"background", m.background},
                    {"overlay", m.overlay}};
    return m_mediaCache;
}
void Deck::watch() {
    if (!m_watcher.files().isEmpty())
        m_watcher.removePaths(m_watcher.files());
    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());
    if (m_path.isEmpty())
        return;
    if (QFile::exists(m_path))
        m_watcher.addPath(m_path);
    // The directory reveals a file that was replaced or recreated.
    m_watcher.addPath(QFileInfo(m_path).absolutePath());
}
QString Deck::dialogDirectory() const {
    QSettings settings(QSettings::IniFormat, QSettings::UserScope, "hype", "hype");
    const QString last = settings.value("files/lastDirectory").toString();
    if (!last.isEmpty() && QDir(last).exists())
        return last;
    if (!m_path.isEmpty() && QDir(baseDir()).exists())
        return baseDir();
    const QString documents = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    return !documents.isEmpty() && QDir(documents).exists() ? documents : QDir::homePath();
}
static void rememberPresentation(const QString &path) {
    QSettings settings(QSettings::IniFormat, QSettings::UserScope, "hype", "hype");
    settings.setValue("files/lastDirectory", QFileInfo(path).absolutePath());
    settings.setValue("files/lastPresentation", path);
}
bool Deck::reopenLastPresentation() {
    QSettings settings(QSettings::IniFormat, QSettings::UserScope, "hype", "hype");
    const QString path =
        settings.value("files/lastRecoveryDocument", settings.value("files/lastPresentation"))
            .toString();
    if (path.isEmpty())
        return false;
    if (QFileInfo(path).isFile())
        return loadPath(path);
    if (!settings.contains("files/lastRecoveryDocument"))
        return false;
    // Keep the recovery identity even if Dropbox or another process removed the file.
    m_path = QFileInfo(path).absoluteFilePath();
    m_saved.clear();
    apply(QString(), 0, false);
    m_externalChange = true;
    setStatus("The last presentation is missing. Use Save As to recover it to a new file.");
    return false;
}
bool Deck::loadPath(const QString &path, bool remember) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        setStatus(f.errorString());
        return false;
    }
    QString s = QString::fromUtf8(f.readAll());
    m_path = QFileInfo(path).absoluteFilePath();
    apply(s, 0, false);
    m_saved = s;
    m_undo.clear();
    m_redo.clear();
    m_externalChange = false;
    watch();
    emit changed();
    setStatus("Opened " + title());
    if (remember)
        rememberPresentation(m_path);
    m_recovery.recoverDraft(*this);
    if (m_recovery.active())
        m_recovery.checkpoint(*this);
    return true;
}
bool Deck::validateStructure(const QString &operation) {
    const auto parsed = parseDeck(m_source);
    bool sameSlides = parsed.slides.size() == count();
    for (int i = 0; sameSlides && i < count(); ++i)
        sameSlides = parsed.slides[i].source == m_parsed.slides[i].source;
    if (!parsed.error.isEmpty() || !m_parsed.error.isEmpty() || !sameSlides) {
        const QString problem = !m_parsed.error.isEmpty() ? m_parsed.error :
                                !parsed.error.isEmpty() ? parsed.error : "Unfinished slide boundaries";
        setStatus("Cannot " + operation + ": " + problem +
                  ". Finish the Markdown first; your changes are still in the editor.");
        return false;
    }
    return true;
}
bool Deck::savePath(const QString &path) {
    if (!validateStructure("save"))
        return false;
    if (QFileInfo(path).absoluteFilePath() == m_path && m_externalChange) {
        setStatus("File changed on disk. Use Save As to keep both versions.");
        return false;
    }
    QByteArray previous;
    if (QFile::exists(path)) {
        QFile disk(path);
        if (!disk.open(QIODevice::ReadOnly)) {
            setStatus("Cannot read the existing presentation: " + disk.errorString());
            return false;
        }
        previous = disk.readAll();
        if (disk.error() != QFile::NoError) {
            setStatus("Cannot read the existing presentation: " + disk.errorString());
            return false;
        }
        if (QFileInfo(path).absoluteFilePath() == m_path && QString::fromUtf8(previous) != m_saved) {
            m_externalChange = true;
            setStatus("File changed on disk. Save a copy or reopen.");
            return false;
        }
    }
    const QByteArray next = m_source.toUtf8();
    const QFileInfo target(path);
    const QString backupPrefix = target.fileName() + ".";
    QDir backups(target.absolutePath() + "/.hype-backups");
    if (!previous.isEmpty() && previous != next) {
        const QString stamp = QDateTime::currentDateTimeUtc().toString("yyyyMMdd-HHmmss-zzz");
        const QString hash = QString::fromLatin1(QCryptographicHash::hash(previous, QCryptographicHash::Sha256).toHex().left(16));
        QSaveFile backup(backups.filePath(backupPrefix + stamp + "-" + hash + ".bak"));
        if (!QDir().mkpath(backups.absolutePath()) || !backup.open(QIODevice::WriteOnly) ||
            backup.write(previous) != previous.size() || !backup.commit()) {
            setStatus("Could not create a recovery backup. The saved presentation was left untouched.");
            return false;
        }
    }
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly) || f.write(next) != next.size() || !f.commit()) {
        setStatus(f.errorString());
        return false;
    }
    // Keep every saved version. Autosaving must not age the last good deck out
    // of a small rolling backup window.
    if (QFileInfo(path).absoluteFilePath() != m_path)
        m_recovery.retireDraft(*this);
    m_path = QFileInfo(path).absoluteFilePath();
    m_saved = m_source;
    m_externalChange = false;
    watch();
    emit changed();
    setStatus("Saved");
    rememberPresentation(m_path);
    if (m_recovery.active())
        m_recovery.checkpoint(*this);
    return true;
}
bool Deck::confirmDiscard() {
    if (m_recovery.active())
        return m_recovery.flushAutosave(*this);
    if (!dirty())
        return true;
    setStatus("Save this presentation before opening another one.");
    return false;
}
void Deck::openDialog() {
    if (!confirmDiscard())
        return;
    QString error;
    const QString p = FileDialog::choose(false, dialogDirectory(), "Markdown", {"*.md"}, &error);
    if (!error.isEmpty()) setStatus(error);
    if (!p.isEmpty() && loadPath(p))
        emit opened(true);
}
void Deck::save() {
    if (m_recovery.active() && !m_recovery.checkpoint(*this))
        return;
    if (m_path.isEmpty())
        saveAs();
    else
        savePath(m_path);
}
void Deck::saveAs() {
    QString error;
    const QString p = FileDialog::choose(true,
        QDir(dialogDirectory())
            .filePath(m_path.isEmpty() ? "presentation.md" : QFileInfo(m_path).fileName()),
        "Markdown", {"*.md"}, &error);
    if (!error.isEmpty()) setStatus(error);
    if (p.isEmpty())
        return;
    saveCopyPath(p);
}
bool Deck::saveCopyPath(const QString &path) {
    if (!validateStructure("save"))
        return false;
    if (m_path.isEmpty() || QFileInfo(path).absolutePath() == baseDir())
        return savePath(path);
    const QDir destination(QFileInfo(path).absolutePath());
    QTemporaryDir staging(destination.filePath(".hype-save-XXXXXX"));
    if (!staging.isValid()) {
        setStatus("Could not prepare the presentation directory.");
        return false;
    }
    QList<QPair<QString, QString>> copies;
    // Check every collision before publishing anything; compare streams so a
    // large video never requires two whole-file buffers in the editor.
    for (const QString &kind : {QString("images"), QString("videos")}) {
        const QDir source(baseDir() + '/' + kind);
        for (const auto &name : source.entryList(QDir::Files)) {
            const QString relative = kind + '/' + name;
            const QString target = destination.filePath(relative);
            if (QFile::exists(target)) {
                QFile a(source.filePath(name)), b(target);
                QCryptographicHash ah(QCryptographicHash::Sha256), bh(QCryptographicHash::Sha256);
                if (!a.open(QIODevice::ReadOnly) || !b.open(QIODevice::ReadOnly) ||
                    !ah.addData(&a) || !bh.addData(&b)) {
                    setStatus("Could not read media while copying");
                    return false;
                }
                if (ah.result() != bh.result()) {
                    setStatus("Save As media collision: " + name);
                    return false;
                }
            } else {
                QDir().mkpath(staging.filePath(kind));
                const QString staged = staging.filePath(relative);
                if (!QFile::copy(source.filePath(name), staged)) {
                    setStatus("Could not copy " + name);
                    return false;
                }
                copies.append({staged, target});
            }
        }
    }
    QStringList published, directories;
    auto rollback = [&] {
        for (const auto &file : published)
            QFile::remove(file);
        for (const auto &directory : directories)
            QDir().rmdir(directory);
    };
    for (const auto &copy : copies) {
        const QString directory = QFileInfo(copy.second).absolutePath();
        if (!QDir(directory).exists()) {
            if (!QDir().mkpath(directory)) {
                rollback();
                setStatus("Could not create media directory");
                return false;
            }
            directories << directory;
        }
        if (!QFile::rename(copy.first, copy.second)) {
            rollback();
            setStatus("Could not publish copied media");
            return false;
        }
        published << copy.second;
    }
    if (savePath(path))
        return true;
    rollback();
    return false;
}

void Deck::newDeck() {
    if (!confirmDiscard())
        return;
    m_path.clear();
    m_saved.clear();
    m_externalChange = false;
    apply("---\ntitle: Untitled\ntheme: tokyo-night\n---\n\n# Your next idea\n", 0);
    m_undo.clear();
    m_redo.clear();
    watch();
    if (m_recovery.active()) {
        m_recovery.resetCheckpoint();
        m_recovery.checkpoint(*this);
    }
    emit opened(false);
}
void Deck::enableAutosave(const QString &recoveryDirectory) {
    m_recovery.enableAutosave(*this, recoveryDirectory);
}
bool Deck::flushAutosave() {
    return m_recovery.flushAutosave(*this);
}
QVariantList Deck::recoveryVersions() const {
    return m_recovery.versions(*this);
}
bool Deck::restoreVersion(const QString &name) {
    return m_recovery.restoreVersion(*this, name);
}
void Deck::importDialog() {
    QString error;
    const QString p = FileDialog::choose(false, baseDir(), "Media",
        {"*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.svg",
         "*.mp4", "*.mov", "*.mkv", "*.webm", "*.m4v"}, &error);
    if (!error.isEmpty()) setStatus(error);
    if (!p.isEmpty())
        m_assets.importMedia(*this, QUrl::fromLocalFile(p));
}
bool Deck::importMedia(const QUrl &url, bool newSlide) {
    return m_assets.importMedia(*this, url, newSlide);
}
bool Deck::pasteMedia() {
    return m_assets.pasteMedia(*this);
}
void Deck::cancelPaste() {
    m_assets.cancelPaste(*this);
}
QString Deck::savePastedMedia(const QString &value) {
    return m_assets.savePastedMedia(*this, value);
}
QStringList Deck::notes(int index) const {
    return slideNotes(slide(index));
}
QString Deck::renderId(int index) const {
    auto &cached = m_renderIds[index];
    const QString source = slide(index), base = baseDir();
    const auto colors = palette();
    if (cached.source == source && cached.base == base && cached.palette == colors &&
        cached.clock.isValid() && cached.clock.elapsed() < 1000)
        return cached.id;
    QByteArray bytes;
    QDataStream stream(&bytes, QIODevice::WriteOnly);
    stream << slide(index) << baseDir() << palette();
    auto media = parseMedia(slide(index), baseDir());
    for (const QString &path : {media.path, media.poster}) {
        QFileInfo file(path);
        stream << file.lastModified().toMSecsSinceEpoch() << file.size();
    }
    cached.source = source;
    cached.base = base;
    cached.palette = colors;
    cached.clock.start();
    cached.id = QString::fromLatin1(
        bytes.toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
    return cached.id;
}
void Deck::matchImageBackground(bool enabled) {
    setMediaBackground(enabled ? "auto" : "theme");
}
void Deck::setMediaBackground(const QString &mode) {
    if (!QStringList{"auto", "theme", "blur", "white", "black"}.contains(mode))
        return;
    auto media = parseMedia(slideSource(), baseDir());
    if (media.file.isEmpty())
        return;
    // A background only shows around fitted media, so choosing one stops the media spanning.
    const bool fittedBackground = mode == "blur" || mode == "white" || mode == "black" ||
                                  (media.video && mode == "auto");
    QStringList remove{"background"}, add{"background=" + mode};
    if (fittedBackground) {
        remove << "span" << "fit";
        add.prepend("fit");
    }
    editSlide(withMediaDirectives(slideSource(), remove, add));
}
void Deck::setMediaMode(const QString &mode) {
    if (!QStringList{"fit", "span"}.contains(mode))
        return;
    editSlide(withMediaDirectives(slideSource(), {"fit", "span"}, {mode}));
}
// Puts the media beside the text ("left" or "right"), or back under it ("none").
void Deck::setMediaSide(const QString &side) {
    if (!QStringList{"left", "right", "none"}.contains(side))
        return;
    if (parseMedia(slideSource(), baseDir()).file.isEmpty())
        return;
    editSlide(withMediaDirectives(slideSource(), {"left", "right"}, side == "none" ? QStringList() : QStringList{side}));
}
void Deck::exportDialog(const QString &format) {
    if (m_exporting)
        return;
    QString error;
    const QString p = FileDialog::choose(
        true,
        baseDir() + "/" + QString(title()).replace(QRegularExpression(R"([/\\\x00-\x1f])"), "-") +
            "." + format,
        format.toUpper(), {"*." + format}, &error);
    if (!error.isEmpty()) setStatus(error);
    if (p.isEmpty())
        return;
    startExport(format, p);
}
static void stopExport(QProcess *process) {
    if (process && process->processId() > 0) {
        // Include any FFmpeg child processes in cancellation.
        ::kill(-process->processId(), SIGKILL);
        process->kill();
    }
}
Deck::~Deck() {
    if (m_exportProcess) {
        disconnect(m_exportProcess, nullptr, this, nullptr);
        if (m_exportProcess->state() == QProcess::Starting)
            m_exportProcess->waitForStarted(1000);
        stopExport(m_exportProcess);
        m_exportProcess->waitForFinished(1000);
    }
}
void Deck::cancelExport() {
    if (!m_exporting) return;
    m_exportCancelled = true;
    stopExport(m_exportProcess);
}
bool Deck::loadExportSnapshot(const QString &path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        setStatus(file.errorString());
        return false;
    }
    const auto snapshot = QJsonDocument::fromJson(file.readAll()).object();
    if (!snapshot["source"].isString() || !snapshot["path"].isString()) {
        setStatus("Invalid export snapshot.");
        return false;
    }
    m_path = snapshot["path"].toString();
    m_source = snapshot["source"].toString();
    m_parsed = parseDeck(m_source);
    m_paletteHeader = m_parsed.header;
    m_paletteCache = snapshot["palette"].toObject().toVariantMap();
    return validateStructure("export");
}
void Deck::startExport(const QString &format, const QString &path) {
    if (m_exporting || path.isEmpty() || !QStringList{"pdf", "pptx", "html"}.contains(format))
        return;
    if (!validateStructure("export")) {
        m_exportFailed = true;
        m_exportStatus = m_status;
        emit exportChanged();
        emit exportFinished(false);
        return;
    }
    auto temporary = std::make_shared<QTemporaryDir>();
    const QString destination = QFileInfo(path).absoluteFilePath();
    auto staged = std::make_shared<QTemporaryDir>(QFileInfo(destination).absolutePath() + "/.hype-export-XXXXXX");
    QFile snapshot(temporary->filePath("presentation.json"));
    const QByteArray data = QJsonDocument(QJsonObject{
        {"source", m_source},
        {"path", m_path.isEmpty() ? baseDir() + "/Untitled.md" : m_path},
        {"palette", QJsonObject::fromVariantMap(palette())}}).toJson();
    if (!temporary->isValid() || !staged->isValid() || !snapshot.open(QIODevice::WriteOnly) || snapshot.write(data) != data.size()) {
        m_exportFailed = true;
        m_exportStatus = "Could not prepare the export.";
        emit exportChanged();
        emit exportFinished(false);
        return;
    }
    snapshot.close();
    m_exporting = true;
    m_exportCancelled = false;
    m_exportFailed = false;
    m_exportProgress = 0;
    m_exportStatus = "Preparing " + format.toUpper() + " export…";
    emit exportChanged();
    auto *process = new QProcess(this);
    m_exportProcess = process;
    process->setUnixProcessParameters(QProcess::UnixProcessFlag::CreateNewSession);
    connect(process, &QProcess::started, this, [this, process] {
        if (m_exportCancelled) stopExport(process);
    });
    // A separate renderer keeps Qt painting, compression and video conversion
    // away from the editor. It reads an immutable snapshot, including unsaved edits.
    auto environment = QProcessEnvironment::systemEnvironment();
    environment.insert("QT_QPA_PLATFORM", "offscreen");
    environment.insert("QT_QPA_PLATFORMTHEME", "generic");
    environment.insert("TMPDIR", temporary->path());
    process->setProcessEnvironment(environment);
    auto pending = std::make_shared<QByteArray>();
    auto failure = std::make_shared<QString>();
    auto diagnostics = std::make_shared<QByteArray>();
    auto readProgress = [this, process, pending, failure] {
        pending->append(process->readAllStandardOutput());
        int end;
        while ((end = pending->indexOf('\n')) >= 0) {
            const auto event = QJsonDocument::fromJson(pending->left(end)).object();
            pending->remove(0, end + 1);
            if (event.contains("error")) *failure = event["error"].toString();
            if (!event.contains("progress")) continue;
            m_exportProgress = qBound(0.0, event["progress"].toDouble(), 1.0);
            m_exportStatus = event["message"].toString();
            emit exportChanged();
        }
    };
    connect(process, &QProcess::readyReadStandardOutput, this, readProgress);
    connect(process, &QProcess::readyReadStandardError, this, [process, diagnostics] {
        *diagnostics = (*diagnostics + process->readAllStandardError()).right(8192);
    });
    auto completed = std::make_shared<bool>(false);
    auto finish = [this, process, temporary, staged, completed, destination](bool success, QString message) {
        if (*completed) return;
        *completed = true;
        success = success && !m_exportCancelled;
        if (success && ::rename(QFile::encodeName(staged->filePath("output")).constData(),
                                QFile::encodeName(destination).constData()) != 0) {
            success = false;
            message = "Could not save the export: " + QString::fromLocal8Bit(std::strerror(errno));
        }
        m_exporting = false;
        m_exportProcess = nullptr;
        m_exportFailed = !success && !m_exportCancelled;
        if (success) m_exportProgress = 1;
        m_exportStatus = m_exportCancelled ? "Export cancelled" : success ? "Exported " + QFileInfo(destination).fileName() : "Export failed: " + message;
        process->deleteLater();
        emit exportChanged();
        emit exportFinished(success);
    };
    connect(process, &QProcess::finished, this,
        [process, readProgress, finish, failure, diagnostics](int code, QProcess::ExitStatus exitStatus) {
            readProgress();
            const bool success = exitStatus == QProcess::NormalExit && code == 0;
            QString error = *failure;
            if (error.isEmpty()) error = QString::fromUtf8(*diagnostics + process->readAllStandardError()).trimmed();
            if (error.isEmpty()) error = "The export process stopped unexpectedly.";
            finish(success, error);
        });
    connect(process, &QProcess::errorOccurred, this, [process, finish](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) finish(false, process->errorString());
    });
    process->start(m_exportProgram, {"--export-snapshot", snapshot.fileName(), "--" + format,
                                    staged->filePath("output")});
}
// Snapshots the document for the headless Exporter without copying media.
static Exporter::Snapshot exportSnapshot(const Deck &deck) {
    Exporter::Snapshot snapshot;
    snapshot.baseDir = deck.baseDir();
    snapshot.title = deck.title();
    snapshot.palette = deck.palette();
    for (int i = 0; i < deck.count(); ++i)
        snapshot.slides << deck.slide(i);
    return snapshot;
}

bool Deck::exportPdf(const QString &path) {
    if (!validateStructure("export"))
        return false;
    QString error;
    const bool ok = Exporter::exportPdf(exportSnapshot(*this), path,
        [this](double fraction, const QString &message) { emit exportAdvanced(fraction, message); }, &error);
    if (ok)
        setStatus("Exported " + path);
    else if (!error.isEmpty())
        setStatus(error);
    return ok;
}
bool Deck::renderImages(const QString &directory, int width, bool convertAnimations) {
    if (!validateStructure("export"))
        return false;
    QString error;
    const bool ok = Exporter::renderImages(exportSnapshot(*this), directory, width, convertAnimations,
        [this](double fraction, const QString &message) { emit exportAdvanced(fraction, message); }, &error);
    if (!ok && !error.isEmpty())
        setStatus(error);
    return ok;
}
bool Deck::exportHtml(const QString &path) {
    if (!validateStructure("export"))
        return false;
    QString error;
    const bool ok = Exporter::exportHtml(exportSnapshot(*this), path,
        [this](double fraction, const QString &message) { emit exportAdvanced(fraction, message); }, &error);
    if (ok)
        setStatus("Exported " + path);
    else if (!error.isEmpty())
        setStatus(error);
    return ok;
}
bool Deck::exportPptx(const QString &path) {
    if (!validateStructure("export"))
        return false;
    QString error;
    const bool ok = Exporter::exportPptx(exportSnapshot(*this), path,
        [this](double fraction, const QString &message) { emit exportAdvanced(fraction, message); }, &error);
    if (ok)
        setStatus("Exported " + path);
    else if (!error.isEmpty())
        setStatus(error);
    return ok;
}
