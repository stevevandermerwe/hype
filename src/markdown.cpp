#include "markdown.h"
#include <QRegularExpression>

FencedRanges markdownFences(const QString &source, int from) {
    FencedRanges result;
    static const QRegularExpression fenceRe("^ {0,3}(`{3,}|~{3,})(.*)$");
    int pos = qMax(0, from);
    int open = 0, fenceStart = 0, fenceLength = 0;
    QChar fence;
    auto lineAt = [&](int offset, int *next) {
        int end = source.indexOf('\n', offset);
        *next = end < 0 ? source.size() : end + 1;
        QString line = source.mid(offset, (end < 0 ? source.size() : end) - offset);
        if (line.endsWith('\r'))
            line.chop(1);
        return line;
    };
    int next = 0;
    while (pos < source.size()) {
        const QString line = lineAt(pos, &next);
        const auto match = fenceRe.match(line);
        if (match.hasMatch()) {
            const QString run = match.captured(1);
            if (fenceLength == 0) {
                fence = run[0];
                fenceLength = run.size();
                fenceStart = pos;
                open = pos;
            } else if (run[0] == fence && run.size() >= fenceLength &&
                       match.captured(2).trimmed().isEmpty()) {
                result.ranges.append({open, next});
                fenceLength = 0;
            }
        }
        pos = next;
    }
    if (fenceLength)
        result.unclosedOffset = fenceStart;
    return result;
}

bool insideFence(const FencedRanges &fences, int offset) {
    for (const auto &range : fences.ranges)
        if (offset >= range.first && offset < range.second)
            return true;
    return false;
}
