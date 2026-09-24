#pragma once
#include <QByteArray>
#include <QString>
#include <QUrl>
class Deck;

// Copies, names, and compresses media into a deck's images/ or videos/ directory,
// and manages the pending clipboard paste. Extracted from Deck so media handling
// stays a small, self-contained concern; it reaches back into Deck only through
// that class's public editing and status API.
class AssetStore {
  public:
    bool importMedia(Deck &deck, const QUrl &url, bool newSlide = false);
    bool pasteMedia(Deck &deck);
    QString savePastedMedia(Deck &deck, const QString &name);
    void cancelPaste(Deck &deck);
    bool compressingImage() const { return m_compressingImage; }

  private:
    struct PendingPaste {
        QString source, extension, path, document;
        QByteArray data;
        bool video = false;
        int selected = 0;
    } m_paste;
    bool m_compressingImage = false;
    quint64 m_pasteGeneration = 0;
};
