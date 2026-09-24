#include "assetstore.h"
#include "deck.h"
#include "images.h"
#include "renderer.h"
#include <QClipboard>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFutureWatcher>
#include <QGuiApplication>
#include <QImageReader>
#include <QMimeData>
#include <QRegularExpression>
#include <QtConcurrentRun>
#include <memory>
#include <utility>

bool AssetStore::importMedia(Deck &deck, const QUrl &url, bool newSlide) {
    if (!url.isLocalFile()) {
        deck.setStatus("Choose a local image or video.");
        return false;
    }
    if (deck.path().isEmpty()) {
        deck.saveAs();
        if (deck.path().isEmpty())
            return false;
    }
    QFileInfo info(url.toLocalFile());
    if (!info.isFile())
        return false;
    const bool video = QStringList{"mp4", "mov", "mkv", "webm", "m4v"}.contains(info.suffix().toLower());
    if (!video && !QImageReader(info.absoluteFilePath()).canRead()) {
        deck.setStatus("Choose a supported image or video.");
        return false;
    }
    const QString dir = deck.baseDir() + (video ? "/videos" : "/images");
    QDir().mkpath(dir);
    QString name = info.fileName(), dest = dir + "/" + name;
    int suffix = 2;
    QFile input(info.absoluteFilePath());
    if (!input.open(QIODevice::ReadOnly)) {
        deck.setStatus(input.errorString());
        return false;
    }
    QCryptographicHash inputHash(QCryptographicHash::Sha256);
    if (!inputHash.addData(&input)) {
        deck.setStatus(input.errorString());
        return false;
    }
    const auto hash = inputHash.result();
    while (QFile::exists(dest)) {
        QFile old(dest);
        if (!old.open(QIODevice::ReadOnly)) {
            deck.setStatus("Cannot read existing media: " + name);
            return false;
        }
        QCryptographicHash oldHash(QCryptographicHash::Sha256);
        if (!oldHash.addData(&old)) {
            deck.setStatus(old.errorString());
            return false;
        }
        if (oldHash.result() == hash)
            break;
        name = info.completeBaseName() + "-" + QString::number(suffix++) + "." + info.suffix();
        dest = dir + "/" + name;
    }
    if (!QFile::exists(dest) && !QFile::copy(info.absoluteFilePath(), dest)) {
        deck.setStatus("Could not import " + name);
        return false;
    }
    if (newSlide)
        deck.addSlide();
    deck.editSlide(withMedia(deck.slideSource(), "![](<" + name + ">)"));
    deck.setStatus("Added " + name);
    return true;
}

bool AssetStore::pasteMedia(Deck &deck) {
    if (m_compressingImage)
        return true;
    const QMimeData *clipboard = QGuiApplication::clipboard()->mimeData();
    if (!clipboard)
        return false;
    QString source, extension, suggested = "image";
    bool video = false;
    QImage image;
    QByteArray mediaData;
    // Prefer copied files to thumbnail image data supplied by file managers.
    for (const QUrl &url : clipboard->urls()) {
        if (!url.isLocalFile())
            continue;
        QFileInfo file(url.toLocalFile());
        const QString suffix = file.suffix().toLower();
        const bool isVideo = QStringList{"mp4", "mov", "mkv", "webm", "m4v"}.contains(suffix);
        if (!file.isFile() || (!isVideo && !QImageReader(file.absoluteFilePath()).canRead()))
            continue;
        source = file.absoluteFilePath();
        extension = suffix;
        suggested = file.completeBaseName();
        video = isVideo;
        break;
    }
    if (source.isEmpty()) {
        const QMap<QString, QString> formats{{"video/mp4", "mp4"},
                                             {"video/webm", "webm"},
                                             {"video/quicktime", "mov"},
                                             {"video/x-matroska", "mkv"}};
        for (auto it = formats.cbegin(); it != formats.cend(); ++it) {
            if (!clipboard->hasFormat(it.key()))
                continue;
            mediaData = clipboard->data(it.key());
            if (mediaData.isEmpty())
                continue;
            video = true;
            extension = it.value();
            suggested = "video";
            break;
        }
        if (!video) {
            image = QGuiApplication::clipboard()->image();
            if (image.isNull())
                return false;
            extension = "png";
        }
    }
    if (deck.path().isEmpty()) {
        deck.saveAs();
        if (deck.path().isEmpty())
            return true;
    }
    m_paste = {source, extension, deck.path(), deck.source(), mediaData, video, deck.selected()};
    QImageReader reader(source);
    const bool compress = !video && (source.isEmpty() ||
        (!(reader.supportsAnimation() && reader.imageCount() != 1) &&
         reader.format() != "svg" && reader.format() != "svgz"));
    if (!compress) {
        emit deck.pasteRequested(suggested, extension, video);
        return true;
    }
    const auto media = parseMedia(withMedia(deck.slideSource(), "![](<paste.png>)"), deck.baseDir());
    const auto generation = ++m_pasteGeneration;
    m_compressingImage = true;
    emit deck.compressingImageChanged();
    using Result = std::pair<PendingPaste, QString>;
    auto *watcher = new QFutureWatcher<Result>(&deck);
    QObject::connect(watcher, &QFutureWatcher<Result>::finished, &deck, [this, watcher, generation, suggested, &deck] {
        auto result = watcher->result();
        watcher->deleteLater();
        if (generation != m_pasteGeneration)
            return; // Cancelled work must not reopen the naming dialog.
        m_compressingImage = false;
        emit deck.compressingImageChanged();
        if (!result.second.isEmpty()) {
            m_paste = {};
            deck.setStatus(result.second);
            return;
        }
        if (deck.path() != result.first.path || deck.source() != result.first.document ||
            deck.selected() != result.first.selected) {
            m_paste = {};
            deck.setStatus("The slide changed. Paste the image again.");
            return;
        }
        m_paste = std::move(result.first);
        emit deck.pasteRequested(suggested, m_paste.extension, false);
    });
    // Clipboard access stays on the UI thread; decoding, scaling and both lossless
    // encoders work on an independent snapshot without touching the document.
    watcher->setFuture(QtConcurrent::run([pending = m_paste, image, span = media.span]() mutable -> Result {
        const QSize canvas(3840, 2160);
        QSize original;
        if (!pending.source.isEmpty()) {
            QImageReader reader(pending.source);
            original = reader.size();
            if (reader.transformation() & QImageIOHandler::TransformationRotate90)
                original.transpose();
            image = readSizedImage(pending.source, canvas, span);
        } else {
            original = image.size();
            const QSize target = imageSizeForCanvas(original, canvas, span);
            if (target != original)
                image = image.scaled(target, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        }
        if (image.isNull())
            return {{}, "Could not read the pasted image."};
        QString optimizedExtension;
        QByteArray encoded = compressedImage(image, &optimizedExtension);
        if (encoded.isEmpty())
            return {{}, "Could not compress the pasted image."};
        // Keep an already-small JPEG/WebP when it beats the lossless rewrite.
        if (pending.source.isEmpty() || image.size() != original ||
            encoded.size() < QFileInfo(pending.source).size()) {
            pending.source.clear();
            pending.extension = optimizedExtension;
            pending.data = std::move(encoded);
        }
        return {std::move(pending), {}};
    }));
    return true;
}

void AssetStore::cancelPaste(Deck &deck) {
    ++m_pasteGeneration;
    m_paste = {};
    if (m_compressingImage) {
        m_compressingImage = false;
        emit deck.compressingImageChanged();
    }
}

QString AssetStore::savePastedMedia(Deck &deck, const QString &value) {
    if (m_compressingImage)
        return "The image is still being compressed.";
    if (m_paste.extension.isEmpty())
        return "Paste an image or video first.";
    if (deck.path() != m_paste.path || deck.source() != m_paste.document || deck.selected() != m_paste.selected)
        return "The slide changed. Cancel and paste again.";
    QString stem = value.trimmed();
    if (stem.endsWith("." + m_paste.extension, Qt::CaseInsensitive))
        stem.chop(m_paste.extension.size() + 1);
    if (stem.isEmpty() || stem == "." || stem == ".." ||
        stem.contains(QRegularExpression(R"([/\\<>\x00-\x1f])")))
        return "Use a filename without folders or special characters.";
    const QString name = stem + "." + m_paste.extension;
    const QString directory = QDir(deck.baseDir()).filePath(m_paste.video ? "videos" : "images");
    const QString destination = QDir(directory).filePath(name);
    if (QFile::exists(destination))
        return name + " already exists. Choose another name.";
    if (!QDir().mkpath(directory))
        return "Could not create " + directory;
    bool saved = false;
    if (!m_paste.source.isEmpty())
        saved = QFile::copy(m_paste.source, destination);
    else {
        QFile output(destination);
        if (output.open(QIODevice::WriteOnly | QIODevice::NewOnly)) {
            saved = output.write(m_paste.data) == m_paste.data.size();
            saved = output.flush() && saved;
            output.close();
            if (!saved)
                output.remove();
        }
    }
    if (!saved)
        return "Could not save " + name;
    cancelPaste(deck);
    deck.editSlide(withMedia(deck.slideSource(), "![](<" + name + ">)"));
    deck.setStatus("Added " + name);
    return {};
}
