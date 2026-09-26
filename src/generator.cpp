#include "generator.h"
#include "deck.h"
#include "renderer.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QUrl>

namespace {
constexpr int RequestTimeoutMs = 300000;
constexpr int MaxFiles = 40;
constexpr qsizetype MaxFileBytes = 2 * 1024 * 1024;
constexpr int MaxFolderAttempts = 99;
const char *const KeychainService = "hype-ai";
const char *const KeychainAccount = "default";

QSettings settings() { return QSettings(QSettings::IniFormat, QSettings::UserScope, "hype", "ai"); }

QString readResource(const QString &path, QString *error) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        if (error) *error = path + ": " + file.errorString();
        return {};
    }
    return QString::fromUtf8(file.readAll());
}

bool isLocalHost(const QUrl &url) {
    const QString host = url.host();
    return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.endsWith(".localhost");
}

// A wrapping ``` fence some models add around a whole file.
QString unfenced(const QString &text) {
    static const QRegularExpression opening("^```[A-Za-z0-9_-]*[ \\t]*\\n");
    const QString body = text.trimmed();
    const auto match = opening.match(body);
    if (!match.hasMatch() || !body.endsWith("```"))
        return text;
    return body.mid(match.capturedLength(), body.size() - match.capturedLength() - 3).trimmed() + "\n";
}

bool acceptedPath(const QString &path) {
    static const QRegularExpression image("^images/[A-Za-z0-9][A-Za-z0-9._-]*\\.svg$",
                                          QRegularExpression::CaseInsensitiveOption);
    return path == "presentation.md" || image.match(path).hasMatch();
}

// An API error is either a string or an object with a message.
QString errorMessage(const QJsonValue &value) {
    if (value.isString()) return value.toString();
    return value.toObject()["message"].toString();
}
} // namespace

QString defaultOutputRoot() {
    return QDir::homePath() + "/Documents/Hype";
}

AiConfig loadAiConfig() {
    auto store = settings();
    AiConfig config;
    config.endpoint = store.value("endpoint", config.endpoint).toString();
    config.model = store.value("model", config.model).toString();
    config.keyEnv = store.value("keyEnv", config.keyEnv).toString();
    config.templatePath = store.value("templatePath").toString();
    config.outputRoot = store.value("outputRoot").toString();
    return config;
}

void saveAiConfig(const AiConfig &config) {
    auto store = settings();
    store.setValue("endpoint", config.endpoint);
    store.setValue("model", config.model);
    store.setValue("keyEnv", config.keyEnv);
    store.setValue("templatePath", config.templatePath);
    store.setValue("outputRoot", config.outputRoot);
    store.sync();
}

bool keychainAvailable() {
#ifdef Q_OS_MACOS
    return true;
#else
    return false;
#endif
}

QString aiApiKey(const AiConfig &config, QString *source) {
    for (const QString &name : {QString("HYPE_AI_KEY"), config.keyEnv}) {
        const QString value = name.isEmpty() ? QString() : qEnvironmentVariable(name.toUtf8().constData()).trimmed();
        if (!value.isEmpty()) {
            if (source) *source = "environment variable " + name;
            return value;
        }
    }
#ifdef Q_OS_MACOS
    QProcess security;
    security.start("security", {"find-generic-password", "-s", KeychainService, "-a", KeychainAccount, "-w"});
    if (security.waitForFinished(3000) && security.exitCode() == 0) {
        const QString value = QString::fromUtf8(security.readAllStandardOutput()).trimmed();
        if (!value.isEmpty()) {
            if (source) *source = "the macOS Keychain";
            return value;
        }
    }
#endif
    if (source) source->clear();
    return {};
}

bool saveKeychainKey(const QString &key, QString *error) {
#ifdef Q_OS_MACOS
    static const QRegularExpression safe("^[\\x21-\\x7e]+$");
    const QString trimmed = key.trimmed();
    if (!safe.match(trimmed).hasMatch() || trimmed.contains('\'') || trimmed.contains('\\')) {
        if (error) *error = "The key contains characters that cannot be stored.";
        return false;
    }
    // `security -i` reads the command from stdin, so the key never appears in the process list.
    QProcess security;
    security.start("security", {"-i"});
    security.write(QString("add-generic-password -U -s %1 -a %2 -w '%3'\nexit\n")
                       .arg(KeychainService, KeychainAccount, trimmed).toUtf8());
    security.closeWriteChannel();
    if (!security.waitForFinished(5000) || security.exitCode() != 0) {
        if (error) *error = "Could not save to the Keychain: " + QString::fromUtf8(security.readAllStandardError()).trimmed();
        return false;
    }
    return true;
#else
    Q_UNUSED(key);
    if (error) *error = "Keychain storage is only available on macOS. Set an environment variable instead.";
    return false;
#endif
}

QString promptTemplate(const AiConfig &config, QString *error, const QString &mode) {
    QString text = readResource(config.templatePath.isEmpty() ? QString(":/prompt.md") : config.templatePath, error);
    if (text.isEmpty()) return {};
    text.replace("{{format}}", readResource(":/format.md", nullptr).trimmed());
    if (mode == "mindmap")
        text += "\n" + readResource(":/mindmap.md", nullptr).trimmed() + "\n";
    return text;
}

QByteArray buildChatRequest(const QString &model, const QString &system, const QString &prompt) {
    const QJsonObject body{{"model", model},
                           {"messages", QJsonArray{QJsonObject{{"role", "system"}, {"content", system}},
                                                   QJsonObject{{"role", "user"}, {"content", prompt}}}}};
    return QJsonDocument(body).toJson(QJsonDocument::Compact);
}

ChatReply parseChatReply(const QByteArray &body) {
    const auto document = QJsonDocument::fromJson(body);
    if (!document.isObject())
        return {{}, "The endpoint did not return JSON. Check the endpoint URL."};
    const auto root = document.object();
    if (root.contains("error")) {
        const QString message = errorMessage(root["error"]);
        return {{}, message.isEmpty() ? "The endpoint returned an error." : message};
    }
    const auto choice = root["choices"].toArray().first().toObject();
    const auto content = choice["message"].toObject()["content"];
    QString text;
    if (content.isString())
        text = content.toString();
    else
        for (const auto &part : content.toArray()) // Some providers return content parts.
            text += part.toObject()["text"].toString();
    if (text.trimmed().isEmpty())
        return {{}, "The model returned no content."};
    if (choice["finish_reason"].toString() == "length")
        return {{}, "The model ran out of output tokens before finishing. Ask for fewer slides or use a model with a larger output limit."};
    return {text, {}};
}

GeneratedFiles parseGeneratedFiles(const QString &text) {
    static const QRegularExpression marker("^=== FILE: (.+?) ===$");
    GeneratedFiles result;
    QString path, body;
    bool inFile = false;
    auto flush = [&] {
        if (!inFile || !acceptedPath(path) || result.files.size() >= MaxFiles) return;
        const QByteArray bytes = unfenced(body).trimmed().toUtf8() + "\n";
        if (bytes.size() <= MaxFileBytes)
            result.files.insert(path, bytes);
    };
    for (const QString &line : text.split('\n')) {
        const auto match = marker.match(line.trimmed());
        if (match.hasMatch()) {
            flush();
            path = match.captured(1).trimmed();
            body.clear();
            inFile = true;
        } else if (inFile)
            body += line + '\n';
    }
    flush();
    if (!inFile) {
        // No markers: accept a bare Markdown deck rather than throw the reply away.
        const QString bare = unfenced(text).trimmed();
        if (bare.contains("\n---") && bare.contains("# "))
            result.files.insert("presentation.md", bare.toUtf8() + "\n");
    }
    if (!result.files.contains("presentation.md"))
        result.error = "The reply did not contain a presentation.md. Try again, or use a more capable model.";
    return result;
}

QString slugify(const QString &title) {
    QString slug = title.toLower().normalized(QString::NormalizationForm_D);
    slug.replace(QRegularExpression("[^a-z0-9]+"), "-");
    slug.remove(QRegularExpression("^-+|-+$"));
    return slug.isEmpty() ? "presentation" : slug.left(60);
}

Written writePresentation(const GeneratedFiles &generated, const QString &directory, const QString &parent,
                          const QString &theme) {
    Written written;
    if (!generated.files.contains("presentation.md")) {
        written.error = "Nothing to write: no presentation.md.";
        return written;
    }
    const QString title =
        scalar(parseDeck(QString::fromUtf8(generated.files["presentation.md"])).header, "title", "presentation");
    QString target;
    if (!directory.isEmpty()) {
        target = QDir(directory).absolutePath();
        if (QFileInfo::exists(target) && !QDir(target).isEmpty(QDir::AllEntries | QDir::NoDotAndDotDot)) {
            written.error = target + " already exists and is not empty.";
            return written;
        }
    } else {
        const QString base = QDir(parent).absoluteFilePath(slugify(title));
        target = base;
        for (int n = 2; QFileInfo::exists(target) && n <= MaxFolderAttempts; ++n)
            target = base + "-" + QString::number(n);
        if (QFileInfo::exists(target)) {
            written.error = "Could not find a free folder name beside " + base;
            return written;
        }
    }
    const QDir folder(target);
    if (!folder.mkpath("images") || !folder.mkpath("videos")) {
        written.error = "Could not create " + target;
        return written;
    }
    for (auto it = generated.files.cbegin(); it != generated.files.cend(); ++it) {
        QSaveFile file(folder.filePath(it.key()));
        if (!file.open(QIODevice::WriteOnly) || file.write(it.value()) < 0 || !file.commit()) {
            written.error = file.fileName() + ": " + file.errorString();
            return written;
        }
    }
    written.presentation = folder.filePath("presentation.md");
    // Choosing a theme also records its colors, so the file renders the same anywhere.
    Deck deck;
    if (!theme.isEmpty() && !deck.themeNames().contains(theme))
        written.warnings << "Theme " + theme + " is not installed; kept the default.";
    if (!deck.loadPath(written.presentation, false)) {
        written.warnings << "Could not read the generated presentation: " + deck.status();
        return written;
    }
    const QString chosen = !theme.isEmpty() && deck.themeNames().contains(theme) ? theme : deck.themeName();
    deck.chooseTheme(chosen);
    QSaveFile file(written.presentation);
    if (file.open(QIODevice::WriteOnly) && file.write(deck.source().toUtf8()) >= 0)
        file.commit();
    for (int i = 0; i < deck.count(); ++i)
        for (const QString &problem : slideProblems(deck.slide(i), deck.baseDir()))
            written.warnings << QString("Slide %1: %2").arg(i + 1).arg(problem);
    return written;
}

Generator::Generator(QObject *parent)
    : QObject(parent), m_config(loadAiConfig()), m_network(new QNetworkAccessManager(this)) {
    m_ticker.setInterval(1000);
    connect(&m_ticker, &QTimer::timeout, this, [this] {
        setStatus(QString("Generating… %1s (this can take a minute)").arg(m_elapsed.elapsed() / 1000));
    });
}

QString Generator::keySource() const {
    QString source;
    aiApiKey(m_config, &source);
    return source;
}

void Generator::setConfig(const AiConfig &config) {
    m_config = config;
    emit configChanged();
}
void Generator::setEndpoint(const QString &value) { m_config.endpoint = value.trimmed(); emit configChanged(); }
void Generator::setModel(const QString &value) { m_config.model = value.trimmed(); emit configChanged(); }
void Generator::setKeyEnv(const QString &value) { m_config.keyEnv = value.trimmed(); emit configChanged(); }
void Generator::setTemplatePath(const QString &value) { m_config.templatePath = value.trimmed(); emit configChanged(); }
void Generator::setOutputRoot(const QString &value) { m_config.outputRoot = value.trimmed(); emit configChanged(); }
void Generator::saveSettings() { saveAiConfig(m_config); }

QString Generator::storeKey(const QString &key) {
    QString error;
    if (!saveKeychainKey(key, &error)) return error;
    emit configChanged();
    return {};
}

void Generator::setStatus(const QString &status) {
    m_status = status;
    emit statusChanged();
}

void Generator::fail(const QString &message) {
    setStatus(message);
    emit failed(message);
}

void Generator::cancel() {
    if (m_reply) m_reply->abort();
}

void Generator::generate(const QString &prompt, const QString &theme, const QString &directory,
                         const QString &mode) {
    if (busy()) return;
    if (prompt.trimmed().isEmpty())
        return fail(mode == "mindmap" ? "Paste your mind map first." : "Describe the presentation you want.");
    const QUrl url(m_config.endpoint);
    if (!url.isValid() || (url.scheme() != "https" && url.scheme() != "http") || url.host().isEmpty())
        return fail("The endpoint must be an http(s) URL, such as " + QString(DefaultAiEndpoint));
    if (m_config.model.isEmpty()) return fail("Choose a model.");
    QString error;
    const QString system = promptTemplate(m_config, &error, mode);
    if (system.isEmpty()) return fail("Could not read the prompt template. " + error);
    const QString key = aiApiKey(m_config);
    if (key.isEmpty() && !isLocalHost(url))
        return fail("No API key. Set " + (m_config.keyEnv.isEmpty() ? QString("HYPE_AI_KEY") : m_config.keyEnv) +
                    " in the environment" + (keychainAvailable() ? ", or save one to the Keychain." : "."));
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    if (!key.isEmpty()) request.setRawHeader("Authorization", "Bearer " + key.toUtf8());
    request.setRawHeader("X-Title", "Hype");
    request.setTransferTimeout(RequestTimeoutMs);
    QNetworkReply *reply = m_network->post(request, buildChatRequest(m_config.model, system, prompt.trimmed()));
    m_reply = reply;
    m_elapsed.start();
    m_ticker.start();
    setStatus("Generating…");
    connect(reply, &QNetworkReply::finished, this, [this, reply, theme, directory] { finish(reply, theme, directory); });
    emit busyChanged();
}

void Generator::finish(QNetworkReply *reply, const QString &theme, const QString &directory) {
    reply->deleteLater();
    m_reply.clear();
    m_ticker.stop();
    emit busyChanged();
    if (reply->error() == QNetworkReply::OperationCanceledError)
        return setStatus("Cancelled");
    const QByteArray body = reply->readAll();
    const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const ChatReply parsed = parseChatReply(body);
    if (!parsed.error.isEmpty())
        return fail(body.isEmpty() ? reply->errorString()
                                   : (http >= 400 ? QString("HTTP %1: ").arg(http) : QString()) + parsed.error);
    const GeneratedFiles files = parseGeneratedFiles(parsed.content);
    if (!files.error.isEmpty()) return fail(files.error);
    const Written written = writePresentation(files, directory, outputRoot(), theme);
    if (!written.error.isEmpty()) return fail(written.error);
    setStatus("Created " + written.presentation);
    emit succeeded(written.presentation, written.warnings);
}
