#pragma once
#include <QElapsedTimer>
#include <QMap>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QTimer>

class QNetworkAccessManager;
class QNetworkReply;

// AI presentation generation: a prompt and a template go to any OpenAI-compatible
// chat endpoint (OpenRouter by default); the reply becomes a presentation folder.
inline const char *const DefaultAiEndpoint = "https://openrouter.ai/api/v1/chat/completions";
inline const char *const DefaultAiModel = "anthropic/claude-sonnet-4.5";
inline const char *const DefaultAiKeyEnv = "OPENROUTER_API_KEY";

struct AiConfig {
    QString endpoint = DefaultAiEndpoint;
    QString model = DefaultAiModel;
    QString keyEnv = DefaultAiKeyEnv; // Name of the environment variable holding the API key.
    QString templatePath;             // Empty: the bundled template.
    QString outputRoot;               // Empty: ~/Documents/Hype.
};
AiConfig loadAiConfig();
void saveAiConfig(const AiConfig &config);
QString defaultOutputRoot();

// The API key is never stored in the settings file: it comes from the environment
// (HYPE_AI_KEY, else the variable named by keyEnv) or, on macOS, the login Keychain.
QString aiApiKey(const AiConfig &config, QString *source = nullptr);
bool saveKeychainKey(const QString &key, QString *error);
bool keychainAvailable();

// The system prompt: the template with {{format}} replaced by Hype's format guide.
QString promptTemplate(const AiConfig &config, QString *error);
QByteArray buildChatRequest(const QString &model, const QString &system, const QString &prompt);
struct ChatReply {
    QString content, error;
};
ChatReply parseChatReply(const QByteArray &body);

// The model answers with "=== FILE: path ===" sections. Only presentation.md and
// images/<name>.svg are accepted, so a reply can never write outside its folder.
struct GeneratedFiles {
    QMap<QString, QByteArray> files;
    QString error;
};
GeneratedFiles parseGeneratedFiles(const QString &text);
QString slugify(const QString &title);

struct Written {
    QString presentation; // Path of presentation.md.
    QStringList warnings;
    QString error;
};
// Writes the folder: into `directory` when given (it must be new or empty),
// otherwise into a new folder named after the title under `parent`.
Written writePresentation(const GeneratedFiles &generated, const QString &directory, const QString &parent,
                          const QString &theme);

class Generator : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString endpoint READ endpoint WRITE setEndpoint NOTIFY configChanged)
    Q_PROPERTY(QString model READ model WRITE setModel NOTIFY configChanged)
    Q_PROPERTY(QString keyEnv READ keyEnv WRITE setKeyEnv NOTIFY configChanged)
    Q_PROPERTY(QString templatePath READ templatePath WRITE setTemplatePath NOTIFY configChanged)
    Q_PROPERTY(QString outputRoot READ outputRoot WRITE setOutputRoot NOTIFY configChanged)
    Q_PROPERTY(QString keySource READ keySource NOTIFY configChanged)
    Q_PROPERTY(bool canStoreKey READ canStoreKey CONSTANT)
  public:
    explicit Generator(QObject *parent = nullptr);
    bool busy() const { return m_reply != nullptr; }
    QString status() const { return m_status; }
    QString endpoint() const { return m_config.endpoint; }
    QString model() const { return m_config.model; }
    QString keyEnv() const { return m_config.keyEnv; }
    QString templatePath() const { return m_config.templatePath; }
    QString outputRoot() const { return m_config.outputRoot.isEmpty() ? defaultOutputRoot() : m_config.outputRoot; }
    QString keySource() const;
    bool canStoreKey() const { return keychainAvailable(); }
    void setEndpoint(const QString &value);
    void setModel(const QString &value);
    void setKeyEnv(const QString &value);
    void setTemplatePath(const QString &value);
    void setOutputRoot(const QString &value);
    const AiConfig &config() const { return m_config; }
    void setConfig(const AiConfig &config);

    Q_INVOKABLE void saveSettings();
    Q_INVOKABLE QString storeKey(const QString &key); // Returns an error, or empty.
    Q_INVOKABLE void generate(const QString &prompt, const QString &theme = {}, const QString &directory = {});
    Q_INVOKABLE void cancel();
  signals:
    void busyChanged();
    void statusChanged();
    void configChanged();
    void succeeded(const QString &presentation, const QStringList &warnings);
    void failed(const QString &message);

  private:
    void setStatus(const QString &status);
    void fail(const QString &message);
    void finish(QNetworkReply *reply, const QString &theme, const QString &directory);

    AiConfig m_config;
    QNetworkAccessManager *m_network;
    QPointer<QNetworkReply> m_reply;
    QTimer m_ticker;
    QElapsedTimer m_elapsed;
    QString m_status;
};
