#pragma once
#include <QByteArray>
#include <QString>
#include <QTimer>
#include <QVariantList>
class Deck;

// Crash recovery and autosave: checkpoints the document into
// ~/.local/state/hype/recovery/, restores the latest draft, and serves version
// history. Extracted from Deck; it serializes and restores the document's private
// state, so Deck grants it friendship. Only the public enableAutosave /
// flushAutosave / recoveryVersions / restoreVersion surface remains on Deck.
class Recovery {
  public:
    void enableAutosave(Deck &deck, const QString &directory = {});
    bool checkpoint(Deck &deck);
    bool flushAutosave(Deck &deck);
    QVariantList versions(const Deck &deck) const;
    bool restoreVersion(Deck &deck, const QString &name);
    void recoverDraft(Deck &deck);
    void retireDraft(Deck &deck);
    void resetCheckpoint() {
        m_checkpointSource.clear();
        m_checkpointPath.clear();
    }
    bool active() const { return !m_recoveryDirectory.isEmpty(); }

  private:
    QString folder(const Deck &deck) const;
    bool restoreSnapshot(Deck &deck, const QByteArray &bytes, bool opening);

    QString m_recoveryDirectory;
    QString m_checkpointSource, m_checkpointPath;
    QTimer m_autosaveTimer, m_autosaveDeadline;
    bool m_recovering = false;
};
