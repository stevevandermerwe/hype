#pragma once
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <functional>

// The headless rendering and export pipeline, extracted from Deck so the document
// model stays focused on editing and saving. Each function takes an immutable
// snapshot of the deck plus a progress callback, writes only to the destination,
// and reports failure through `error` rather than touching editor state.
namespace Exporter {
struct Snapshot {
    QStringList slides;
    QString baseDir;
    QString title;
    QVariantMap palette;
};

using Progress = std::function<void(double, const QString &)>;

// Render every slide to PNGs and a slides.json manifest in `directory`.
bool renderImages(const Snapshot &snapshot, const QString &directory, int width,
                  bool convertAnimations, const Progress &progress, QString *error);
bool exportPdf(const Snapshot &snapshot, const QString &path, const Progress &progress, QString *error);
bool exportPptx(const Snapshot &snapshot, const QString &path, const Progress &progress, QString *error);
bool exportHtml(const Snapshot &snapshot, const QString &path, const Progress &progress, QString *error);
} // namespace Exporter
