#include "exporter.h"
#include "animationexport.h"
#include "html.h"
#include "pptx.h"
#include "renderer.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainter>
#include <QPdfWriter>
#include <QSaveFile>
#include <QScopeGuard>
#include <QTemporaryDir>
#include <QThreadPool>
#include <QtConcurrentRun>
#include <atomic>
#include <utility>

namespace Exporter {

// Slides are opaque unless a custom background is translucent. Without an alpha
// channel, PNG encodes a third faster and the file is smaller.
static bool opaque(const QImage &image) {
    for (int y = 0; y < image.height(); ++y) {
        const auto *line = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < image.width(); ++x)
            if (qAlpha(line[x]) != 255)
                return false;
    }
    return true;
}

bool renderImages(const Snapshot &snapshot, const QString &directory, int width,
                  bool convertAnimations, const Progress &progress, QString *error) {
    const QStringList slides = snapshot.slides;
    const QString base = snapshot.baseDir;
    const QVariantMap colors = snapshot.palette;
    const int count = slides.size();
    for (int i = 0; i < count; ++i) {
        const auto errors = slideProblems(slides[i], base);
        if (!errors.isEmpty()) {
            if (error) *error = QString("Slide %1: %2").arg(i + 1).arg(errors.join("; "));
            return false;
        }
    }
    QDir().mkpath(directory);
    // PNG compression dominates export time. Paint and encode slides across the
    // cores, while this thread converts media and reports progress in slide order.
    // Each worker holds a full-size frame, so a few suffice.
    QThreadPool stills;
    stills.setMaxThreadCount(qBound(1, QThread::idealThreadCount(), 8));
    std::atomic_bool stopped = false;
    const auto stop = qScopeGuard([&] {
        stopped = true;
        stills.waitForDone();
    });
    auto stillName = [](int i) { return QString("slide-%1.png").arg(i + 1, 3, 10, QChar('0')); };
    using Still = std::pair<bool, QString>; // Saved, and any rendering warning.
    QList<QFuture<Still>> rendered;
    for (int i = 0; i < count; ++i)
        rendered << QtConcurrent::run(&stills, [&stopped, source = slides[i], base, colors,
                                                width, path = directory + "/" + stillName(i)]() -> Still {
            if (stopped)
                return {false, {}};
            QImage image(width, width * 9 / 16, QImage::Format_ARGB32_Premultiplied);
            image.fill(Qt::transparent);
            QPainter p(&image);
            QString warning;
            paintSlide(&p, image.rect(), source, base, colors, &warning);
            p.end();
            return {opaque(image) ? image.convertToFormat(QImage::Format_RGB32).save(path) : image.save(path), warning};
        });
    QJsonArray manifestSlides;
    QHash<QString, QString> convertedVideos;
    for (int i = 0; i < count; ++i) {
        const double portion = convertAnimations ? 0.8 : 1.0;
        auto report = [&](double fraction, const QString &stage) {
            if (progress)
                progress(portion * (i + fraction) / count,
                         QString("%1 slide %2 of %3").arg(stage).arg(i + 1).arg(count));
        };
        report(0, "Exporting");
        const auto [saved, warning] = rendered[i].result();
        const QString name = stillName(i);
        if (!saved) {
            if (error) *error = "Could not save rendered slide";
            return false;
        }
        auto media = parseMedia(slides[i], base);
        QJsonObject entry{{"image", name}, {"warning", warning}};
        if (media.video) {
            entry["video"] = media.path;
            if (convertAnimations) {
                QString convertError;
                auto movie = convertedVideos.value(media.path);
                if (movie.isEmpty())
                    movie = preparePowerPointVideo(
                        media.path, QString("%1/video-%2.mp4").arg(directory).arg(i + 1), &convertError,
                        [&](double fraction) { report(fraction, "Converting video on"); });
                if (movie.isEmpty()) {
                    if (error) *error = QString("Slide %1: %2").arg(i + 1).arg(convertError);
                    return false;
                }
                convertedVideos.insert(media.path, movie);
                entry["video"] = movie;
            }
            entry["poster"] =
                media.poster.isEmpty() ? ensurePoster(media.path, base) : media.poster;
            entry["span"] = media.span;
            entry["title"] = !media.text.trimmed().isEmpty();
            entry["autoplay"] = media.autoplay;
            entry["loop"] = media.loop;
            entry["muted"] = media.muted;
        }
        if (convertAnimations && !media.video && !media.path.isEmpty()) {
            QImageReader reader(media.path);
            if (reader.supportsAnimation() && reader.imageCount() > 1) {
                const QString movie = QString("animation-%1.mp4").arg(i + 1);
                int repeats = 1;
                QString convertError;
                report(0, "Converting animation");
                if (!exportAnimation(slides[i], base, colors, directory + "/" + movie, width,
                                     &repeats, &convertError,
                                     [&](double fraction) { report(fraction, "Converting animation"); })) {
                    if (error) *error = QString("Slide %1: %2").arg(i + 1).arg(convertError);
                    return false;
                }
                // Composite the complete slide to preserve crop and alpha.
                entry["video"] = movie;
                entry["poster"] = name;
                entry["span"] = true;
                entry["autoplay"] = media.autoplay;
                entry["loop"] = repeats < 0;
                entry["repeatCount"] = repeats;
                entry["muted"] = true;
            }
        }
        if (media.video && media.span) {
            QImage overlay(width, width * 9 / 16, QImage::Format_ARGB32_Premultiplied);
            overlay.fill(Qt::transparent);
            QPainter op(&overlay);
            paintSlide(&op, overlay.rect(), slides[i], base, colors, nullptr, true);
            op.end();
            const QString overlayName = QString("overlay-%1.png").arg(i + 1);
            if (!overlay.save(directory + "/" + overlayName)) {
                if (error) *error = "Could not save video overlay";
                return false;
            }
            entry["overlay_image"] = overlayName;
        }
        manifestSlides.append(entry);
    }
    QFile manifest(directory + "/slides.json");
    if (!manifest.open(QIODevice::WriteOnly))
        return false;
    manifest.write(QJsonDocument(QJsonObject{{"title", snapshot.title}, {"slides", manifestSlides}}).toJson());
    return true;
}

bool exportPdf(const Snapshot &snapshot, const QString &path, const Progress &progress, QString *error) {
    const int count = snapshot.slides.size();
    for (int i = 0; i < count; ++i) {
        const auto errors = slideProblems(snapshot.slides[i], snapshot.baseDir);
        if (!errors.isEmpty()) {
            if (error) *error = QString("Slide %1: %2").arg(i + 1).arg(errors.join("; "));
            return false;
        }
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        if (error) *error = file.errorString();
        return false;
    }
    {
        QPdfWriter writer(&file);
        writer.setPageSize(QPageSize(QSizeF(338.6667, 190.5), QPageSize::Millimeter));
        writer.setPageMargins(QMarginsF(0, 0, 0, 0));
        writer.setResolution(288); // 3840 × 2160 raster budget; text remains vector.
        writer.setTitle(snapshot.title);
        QPainter painter(&writer);
        painter.setRenderHint(QPainter::LosslessImageRendering);
        if (!painter.isActive()) {
            if (error) *error = "Could not initialize PDF painter";
            return false;
        }
        for (int i = 0; i < count; ++i) {
            if (progress)
                progress(double(i) / count, QString("Exporting slide %1 of %2").arg(i + 1).arg(count));
            if (i && !writer.newPage()) {
                if (error) *error = "Could not create PDF page";
                return false;
            }
            paintSlide(&painter, QRectF(0, 0, writer.width(), writer.height()), snapshot.slides[i],
                       snapshot.baseDir, snapshot.palette);
        }
        painter.end();
    }
    if (!file.commit()) {
        if (error) *error = file.errorString();
        return false;
    }
    return true;
}

bool exportHtml(const Snapshot &snapshot, const QString &path, const Progress &progress, QString *error) {
    QTemporaryDir temp;
    if (!renderImages(snapshot, temp.path(), 1920, false, progress, error))
        return false;
    if (progress) progress(1.0, "Packaging HTML…");
    QString writeError;
    if (!writeHtml(temp.path(), path, &writeError)) {
        if (error) *error = "HTML export failed: " + writeError;
        return false;
    }
    return true;
}

bool exportPptx(const Snapshot &snapshot, const QString &path, const Progress &progress, QString *error) {
    QTemporaryDir temp;
    if (!renderImages(snapshot, temp.path(), 3840, true, progress, error))
        return false;
    QString writeError;
    if (progress) progress(0.8, "Packaging PowerPoint…");
    const auto report = [&](double fraction) {
        if (progress) progress(0.8 + 0.2 * fraction, "Packaging PowerPoint…");
    };
    if (!writePptx(temp.path() + "/slides.json", path, &writeError, report)) {
        if (error) *error = "PowerPoint export failed: " + writeError;
        return false;
    }
    return true;
}

} // namespace Exporter
