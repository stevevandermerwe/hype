#include "recovery.h"
#include "deck.h"
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QTimeZone>
#include <chrono>

namespace {
QString digest(const QByteArray &bytes) {
    return QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
}
bool writeAtomically(const QString &path, const QByteArray &bytes) {
    QSaveFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size() && file.commit();
}
}

QString Recovery::folder(const Deck &deck) const {
    return m_recoveryDirectory + '/' + digest((deck.path().isEmpty() ? QString("untitled") : deck.path()).toUtf8());
}
void Recovery::enableAutosave(Deck &deck, const QString &directory) {
    if (!m_recoveryDirectory.isEmpty()) return;
    m_recoveryDirectory = directory.isEmpty()
        ? QStandardPaths::writableLocation(QStandardPaths::StateLocation) + "/recovery" : directory;
    m_autosaveTimer.setSingleShot(true);
    m_autosaveTimer.setInterval(1000);
    m_autosaveDeadline.setSingleShot(true);
    m_autosaveDeadline.setInterval(5000);
    QObject::connect(&m_autosaveTimer, &QTimer::timeout, &deck, [this, &deck] { flushAutosave(deck); });
    QObject::connect(&m_autosaveDeadline, &QTimer::timeout, &deck, [this, &deck] { flushAutosave(deck); });
    QObject::connect(&deck, &Deck::changed, &deck, [this, &deck] {
        if (m_recovering || (deck.source() == m_checkpointSource && deck.path() == m_checkpointPath)) return;
        m_autosaveTimer.start();
        if (!m_autosaveDeadline.isActive()) m_autosaveDeadline.start();
    });
    recoverDraft(deck);
    checkpoint(deck);
    if (deck.dirty() && !deck.path().isEmpty() && !deck.m_externalChange) m_autosaveTimer.start();
}
bool Recovery::checkpoint(Deck &deck) {
    if (m_recoveryDirectory.isEmpty()) return false;
    const QString directory = folder(deck);
    QJsonArray slides;
    for (const auto &slide : deck.m_parsed.slides)
        slides.append(QJsonObject{{"start", slide.start}, {"end", slide.end}});
    const QByteArray bytes = QJsonDocument(QJsonObject{
        {"version", 1}, {"path", deck.m_path}, {"source", deck.m_source}, {"saved", deck.m_saved},
        {"sha256", digest(deck.m_source.toUtf8())}, {"header", deck.m_parsed.header}, {"slides", slides},
        {"selected", deck.m_selected}, {"anchor", deck.m_anchor}, {"conflict", deck.m_externalChange},
        {"timestamp", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)}}).toJson();
    if (!QDir().mkpath(directory + "/versions")) {
        deck.setStatus("Could not create the recovery folder. Changes are still in the editor.");
        return false;
    }
    // Keep every distinct checkpoint. These contain Markdown, never media copies.
    // Write the immutable version before replacing the latest crash-recovery file.
    if (deck.m_source != m_checkpointSource || deck.m_path != m_checkpointPath) {
        const auto order = std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count();
        const QString version = QDateTime::currentDateTimeUtc().toString("yyyyMMdd-HHmmss-zzz") +
            '-' + QString::number(order).rightJustified(20, '0') + '-' +
            digest(deck.m_source.toUtf8()).left(16) + ".json";
        if (!writeAtomically(directory + "/versions/" + version, bytes)) {
            deck.setStatus("Could not back up this version. Changes are still in the editor.");
            return false;
        }
    }
    if (!writeAtomically(directory + "/latest.json", bytes)) {
        deck.setStatus("Could not save the recovery draft. Changes are still in the editor.");
        return false;
    }
    m_checkpointSource = deck.m_source;
    m_checkpointPath = deck.m_path;
    QSettings settings(QSettings::IniFormat, QSettings::UserScope, "hype", "hype");
    settings.setValue("files/lastRecoveryDocument", deck.m_path);
    settings.sync();
    return true;
}
bool Recovery::flushAutosave(Deck &deck) {
    m_autosaveTimer.stop();
    m_autosaveDeadline.stop();
    if (!checkpoint(deck)) return false;
    if (deck.dirty() && !deck.m_path.isEmpty()) {
        const auto parsed = parseDeck(deck.m_source);
        bool complete = parsed.error.isEmpty() && deck.m_parsed.error.isEmpty() && parsed.slides.size() == deck.count();
        for (int i = 0; complete && i < deck.count(); ++i)
            complete = parsed.slides[i].source == deck.m_parsed.slides[i].source;
        if (!complete) deck.setStatus("Draft backed up · finish the Markdown to save the presentation");
        else if (!deck.m_externalChange) {
            deck.savePath(deck.m_path);
        } else deck.setStatus("Draft backed up · file changed outside Hype; use Save As to keep both");
    } else if (deck.m_path.isEmpty()) deck.setStatus("Draft backed up · Ctrl+S to choose a file");
    return true; // A recoverable draft is sufficient to close, even if the file cannot be saved.
}
bool Recovery::restoreSnapshot(Deck &deck, const QByteArray &bytes, bool opening) {
    const auto snapshot = QJsonDocument::fromJson(bytes).object();
    if (snapshot["version"].toInt() != 1 || !snapshot["source"].isString() ||
        snapshot["path"].toString() != deck.m_path || !snapshot["saved"].isString()) return false;
    const QString source = snapshot["source"].toString();
    if (digest(source.toUtf8()) != snapshot["sha256"].toString()) return false;
    ParsedDeck parsed;
    parsed.header = snapshot["header"].toString();
    if (!source.startsWith(parsed.header)) return false;
    const auto slides = snapshot["slides"].toArray();
    int previousEnd = parsed.header.size();
    for (int i = 0; i < slides.size(); ++i) {
        const auto slide = slides[i].toObject();
        const int start = slide["start"].toInt(-1), end = slide["end"].toInt(-1);
        if (start < previousEnd || end < start || end > source.size()) return false;
        const QString separator = source.mid(previousEnd, start - previousEnd);
        const bool terminal = i == slides.size() - 1 && start == source.size() && start == end &&
                              (separator == "---" || separator == "---\r");
        if (i == 0 ? !separator.isEmpty() : !terminal && separator != "---\n" && separator != "---\r\n") return false;
        parsed.slides.append({source.mid(start, end - start), start, end});
        previousEnd = end;
    }
    if (parsed.slides.isEmpty() || previousEnd != source.size()) return false;
    // A clean checkpoint is history, not an unsaved draft. Respect a newer file
    // from Dropbox or another editor instead of resurrecting the old contents.
    if (opening && source == snapshot["saved"].toString() && source != deck.m_saved && !deck.m_saved.isEmpty())
        return true;
    const bool conflict = opening && source != deck.m_saved &&
        (snapshot["conflict"].toBool() || snapshot["saved"].toString() != deck.m_saved);
    m_recovering = true;
    deck.apply(source, snapshot["selected"].toInt(), !opening, snapshot["anchor"].toInt(), &parsed);
    m_recovering = false;
    if (conflict) deck.m_externalChange = true;
    m_checkpointSource = source;
    m_checkpointPath = deck.m_path;
    if (opening && deck.dirty())
        deck.setStatus(conflict ? "Recovered draft · file also changed outside Hype; use Save As to keep both"
                                : "Recovered your last draft");
    if (!opening) deck.setStatus("Restored earlier version");
    return true;
}
void Recovery::recoverDraft(Deck &deck) {
    if (m_recoveryDirectory.isEmpty()) return;
    m_autosaveTimer.stop();
    m_autosaveDeadline.stop();
    m_checkpointSource.clear();
    m_checkpointPath.clear();
    QFile latest(folder(deck) + "/latest.json");
    if (latest.exists() && latest.open(QIODevice::ReadOnly)) {
        const auto bytes = latest.readAll();
        if (QJsonDocument::fromJson(bytes).object()["retired"].toBool()) return;
        if (restoreSnapshot(deck, bytes, true)) return;
    }
    // A crash can occur after writing the immutable version but before publishing latest.json.
    for (const auto &entry : versions(deck)) {
        QFile version(folder(deck) + "/versions/" + entry.toMap()["name"].toString());
        if (version.open(QIODevice::ReadOnly) && restoreSnapshot(deck, version.readAll(), true)) {
            deck.setStatus("Recovered from version history; the latest recovery file was missing or damaged");
            return;
        }
    }
    if (latest.exists())
        deck.setStatus("Could not read the recovery draft. Earlier versions are available in History.");
}
void Recovery::retireDraft(Deck &deck) {
    if (m_recoveryDirectory.isEmpty()) return;
    m_autosaveTimer.stop();
    m_autosaveDeadline.stop();
    // Save As retires the old active draft, but leaves its history available.
    // A marker distinguishes intentional retirement from a missing file after a crash.
    writeAtomically(folder(deck) + "/latest.json", "{\"retired\":true}\n");
}
QVariantList Recovery::versions(const Deck &deck) const {
    QVariantList result;
    if (m_recoveryDirectory.isEmpty()) return result;
    const QDir versions(folder(deck) + "/versions");
    for (const auto &name : versions.entryList({"*.json"}, QDir::Files, QDir::Name | QDir::Reversed)) {
        // Metadata comes from the filename, so opening History doesn't read every document.
        const auto time = QDateTime::fromString(name.left(19), "yyyyMMdd-HHmmss-zzz");
        auto utc = time;
        utc.setTimeZone(QTimeZone::UTC);
        result.append(QVariantMap{{"name", name}, {"label", utc.toLocalTime().toString("yyyy-MM-dd HH:mm:ss.zzz")}});
    }
    return result;
}
bool Recovery::restoreVersion(Deck &deck, const QString &name) {
    if (m_recoveryDirectory.isEmpty() || name != QFileInfo(name).fileName() || !name.endsWith(".json")) return false;
    QFile version(folder(deck) + "/versions/" + name);
    if (!version.open(QIODevice::ReadOnly)) { deck.setStatus("Could not read that version."); return false; }
    if (!checkpoint(deck)) return false;
    if (!restoreSnapshot(deck, version.readAll(), false)) { deck.setStatus("That recovery version is damaged."); return false; }
    // Capture the restoration as a new version; preserve the version being restored.
    resetCheckpoint();
    return flushAutosave(deck);
}
