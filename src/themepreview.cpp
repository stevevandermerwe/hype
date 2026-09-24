#include "themepreview.h"
#include <QColor>
#include <QPainter>

static QColor mix(const QColor &base, const QColor &ink, double amount) {
    return QColor::fromRgbF(base.redF() + (ink.redF() - base.redF()) * amount,
                            base.greenF() + (ink.greenF() - base.greenF()) * amount,
                            base.blueF() + (ink.blueF() - base.blueF()) * amount);
}

QImage renderThemePreview(const QVariantMap &palette, const QSize &size) {
    const qreal W = size.width(), H = size.height();
    const QColor background(palette.value("background", "#1a1b26").toString());
    const QColor foreground(palette.value("foreground", "#c0caf5").toString());
    const QColor accent(palette.value("accent", "#7aa2f7").toString());
    const QColor dim(palette.value("dark_foreground", "#787c99").toString());
    const QColor green(palette.value("green", "#9ece6a").toString());
    const QColor red(palette.value("red", "#f7768e").toString());
    const QColor yellow(palette.value("yellow", "#e0af68").toString());
    const QColor magenta(palette.value("magenta", "#bb9af7").toString());
    const QColor cyan(palette.value("cyan", "#7dcfff").toString());

    QImage image(size, QImage::Format_ARGB32_Premultiplied);
    image.fill(background);
    QPainter p(&image);
    p.setRenderHint(QPainter::Antialiasing);
    const auto block = [&](qreal x, qreal y, qreal w, qreal h, qreal r, const QColor &color) {
        p.setPen(Qt::NoPen);
        p.setBrush(color);
        p.drawRoundedRect(QRectF(x * W, y * H, w * W, h * H), r * W, r * H);
    };

    // Headline, accent rule, and dim body lines.
    block(0.055, 0.10, 0.50, 0.10, 0.030, foreground);
    block(0.055, 0.24, 0.24, 0.035, 0.017, accent);
    block(0.055, 0.36, 0.66, 0.050, 0.025, dim);
    block(0.055, 0.45, 0.58, 0.050, 0.025, dim);
    block(0.055, 0.54, 0.62, 0.050, 0.025, dim);

    // Code block with syntax-colored tokens.
    block(0.055, 0.66, 0.89, 0.28, 0.040, mix(background, accent, 0.14));
    block(0.090, 0.72, 0.16, 0.050, 0.022, magenta);
    block(0.280, 0.72, 0.10, 0.050, 0.022, green);
    block(0.410, 0.72, 0.14, 0.050, 0.022, cyan);
    block(0.090, 0.82, 0.12, 0.050, 0.022, yellow);
    block(0.240, 0.82, 0.18, 0.050, 0.022, red);
    block(0.450, 0.82, 0.16, 0.050, 0.022, foreground);

    p.end();
    return image;
}
