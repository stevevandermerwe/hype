#pragma once
#include <QPair>
#include <QString>
#include <QVector>

// Shared Markdown scanning. The deck parser and the renderer's code masking must
// agree on where fenced code blocks begin and end, so both use this one scanner
// rather than maintaining two copies of the same state machine.
struct FencedRanges {
    // Each range spans [first, second): the opening fence line through the line
    // after the closing fence. Ranges never overlap and appear in source order.
    QVector<QPair<int, int>> ranges;
    // Offset of the opening fence when a fence never closes; -1 otherwise.
    int unclosedOffset = -1;
};

// Scans fenced code blocks (backtick and tilde, length 3 or more). Opening
// fences may carry an info string; closing fences must not. Fences are only
// recognized from `from` onward, matching where the deck parser starts scanning
// after front matter.
FencedRanges markdownFences(const QString &source, int from = 0);

// Whether `offset` falls inside one of the fenced ranges (a line of code).
bool insideFence(const FencedRanges &fences, int offset);
