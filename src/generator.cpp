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

bool acceptedPath(const QString &path, const QString &primary) {
    static const QRegularExpression image("^images/[A-Za-z0-9][A-Za-z0-9._-]*\\.svg$",
                                          QRegularExpression::CaseInsensitiveOption);
    return path == primary || image.match(path).hasMatch();
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
    config.imageEndpoint = store.value("imageEndpoint").toString();
    config.imageModel = store.value("imageModel", config.imageModel).toString();
    return config;
}

void saveAiConfig(const AiConfig &config) {
    auto store = settings();
    store.setValue("endpoint", config.endpoint);
    store.setValue("model", config.model);
    store.setValue("keyEnv", config.keyEnv);
    store.setValue("templatePath", config.templatePath);
    store.setValue("outputRoot", config.outputRoot);
    store.setValue("imageEndpoint", config.imageEndpoint);
    store.setValue("imageModel", config.imageModel);
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

GeneratedFiles parseGeneratedFiles(const QString &text, const QString &primary) {
    static const QRegularExpression marker("^=== FILE: (.+?) ===$");
    GeneratedFiles result;
    QString path, body;
    bool inFile = false;
    auto flush = [&] {
        if (!inFile || !acceptedPath(path, primary) || result.files.size() >= MaxFiles) return;
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
            result.files.insert(primary, bare.toUtf8() + "\n");
    }
    if (!result.files.contains(primary))
        result.error = "The reply did not contain a " + primary + ". Try again, or use a more capable model.";
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

// ---- Changing one slide -------------------------------------------------------------------

namespace {
// True when the text holds a slide separator (or front matter) outside a code fence.
bool hasSlideSeparator(const QString &text) {
    static const QRegularExpression fenceRe("^ {0,3}(`{3,}|~{3,})");
    QString fence;
    for (const QString &raw : text.split('\n')) {
        const QString line = raw.trimmed();
        const auto match = fenceRe.match(raw);
        if (match.hasMatch()) {
            const QString run = match.captured(1);
            if (fence.isEmpty()) fence = run;
            else if (run[0] == fence[0] && run.size() >= fence.size()) fence.clear();
        } else if (fence.isEmpty() && line == "---")
            return true;
    }
    return false;
}

QString uniqueName(const QDir &folder, const QString &name) {
    const QFileInfo info(name);
    QString candidate = name;
    for (int n = 2; folder.exists(candidate) && n <= MaxFolderAttempts; ++n)
        candidate = info.completeBaseName() + "-" + QString::number(n) + "." + info.suffix();
    return candidate;
}
} // namespace

SlideReply parseSlideReply(const QString &text, bool withImages) {
    SlideReply reply;
    QString body;
    if (withImages || text.contains(QRegularExpression("^=== FILE:", QRegularExpression::MultilineOption))) {
        const GeneratedFiles files = parseGeneratedFiles(text, "slide.md");
        if (!files.error.isEmpty()) {
            reply.error = files.error;
            return reply;
        }
        body = QString::fromUtf8(files.files["slide.md"]);
        if (withImages)
            for (auto it = files.files.cbegin(); it != files.files.cend(); ++it)
                if (it.key() != "slide.md")
                    reply.images.insert(it.key(), it.value());
    } else
        body = unfenced(text);
    body = body.trimmed();
    if (body.isEmpty())
        reply.error = "The model returned an empty slide.";
    else if (hasSlideSeparator(body))
        reply.error = "The model returned more than one slide. Try again with a narrower request.";
    else
        reply.slide = body;
    return reply;
}

QString slideRequest(const QString &instruction, const QString &slide, const QString &outline, int index) {
    QStringList lines = outline.split('\n', Qt::SkipEmptyParts);
    if (index >= 0 && index < lines.size())
        lines[index] += "   <- the slide to change";
    return "Outline of the deck:\n" + lines.join('\n') + "\n\nThe slide to change (slide " + QString::number(index + 1) +
           "):\n<slide>\n" + slide.trimmed() + "\n</slide>\n\nRequest: " + instruction.trimmed();
}

QString slideTemplate(const QString &kind, QString *error) {
    QString text = readResource(kind == "diagram" ? ":/slide-diagram.md" : ":/slide-text.md", error);
    if (text.isEmpty()) return {};
    return text.replace("{{format}}", readResource(":/format.md", nullptr).trimmed());
}

QString imagePrompt(const QString &instruction, const QString &slide) {
    const QString title = slideTitle(parseMedia(slide, {}).text);
    return "Create a picture for one presentation slide" + (title.isEmpty() ? QString() : " titled \"" + title + "\"") +
           ". Wide 16:9 composition with a calm area that can sit beside text. Do not draw words, letters or logos "
           "unless the request asks for them.\n\nRequest: " + instruction.trimmed();
}

QByteArray buildImageRequest(const QUrl &endpoint, const QString &model, const QString &prompt) {
    // OpenAI's images endpoint takes a prompt; chat endpoints (OpenRouter) ask for image output.
    QJsonObject body{{"model", model}};
    if (endpoint.path().endsWith("/images/generations")) {
        body["prompt"] = prompt;
        body["n"] = 1;
    } else {
        body["messages"] = QJsonArray{QJsonObject{{"role", "user"}, {"content", prompt}}};
        body["modalities"] = QJsonArray{"image", "text"};
    }
    return QJsonDocument(body).toJson(QJsonDocument::Compact);
}

ImageReply parseImageReply(const QByteArray &body) {
    ImageReply reply;
    const auto document = QJsonDocument::fromJson(body);
    if (!document.isObject()) {
        reply.error = "The endpoint did not return JSON. Check the image endpoint URL.";
        return reply;
    }
    const auto root = document.object();
    if (root.contains("error")) {
        const QString message = errorMessage(root["error"]);
        reply.error = message.isEmpty() ? "The endpoint returned an error." : message;
        return reply;
    }
    QString mime = "image/png";
    QByteArray encoded;
    const auto images = root["choices"].toArray().first().toObject()["message"].toObject()["images"].toArray();
    if (!images.isEmpty()) {
        const QString url = images.first().toObject()["image_url"].toObject()["url"].toString();
        static const QRegularExpression dataUrl("^data:(image/[a-z+.-]+);base64,(.+)$", QRegularExpression::DotMatchesEverythingOption);
        const auto match = dataUrl.match(url);
        if (match.hasMatch()) {
            mime = match.captured(1);
            encoded = match.captured(2).toLatin1();
        }
    } else if (const auto data = root["data"].toArray(); !data.isEmpty())
        encoded = data.first().toObject()["b64_json"].toString().toLatin1();
    if (encoded.isEmpty()) {
        reply.error = "The image model returned no picture. Check that the image model can draw pictures.";
        return reply;
    }
    reply.bytes = QByteArray::fromBase64(encoded);
    if (QImage::fromData(reply.bytes).isNull()) {
        reply.bytes.clear();
        reply.error = "The image model returned data that is not a picture.";
        return reply;
    }
    reply.extension = mime == "image/jpeg" ? "jpg" : mime == "image/webp" ? "webp" : "png";
    return reply;
}

SlideFiles writeSlidePictures(const QString &baseDir, const SlideReply &reply) {
    SlideFiles result{reply.slide, {}};
    const QDir folder(baseDir + "/images");
    if (!reply.images.isEmpty() && !QDir().mkpath(folder.path())) {
        result.error = "Could not create " + folder.path();
        return result;
    }
    for (auto it = reply.images.cbegin(); it != reply.images.cend(); ++it) {
        const QString name = QFileInfo(it.key()).fileName();
        const QString written = uniqueName(folder, name);
        QSaveFile file(folder.filePath(written));
        if (!file.open(QIODevice::WriteOnly) || file.write(it.value()) < 0 || !file.commit()) {
            result.error = file.fileName() + ": " + file.errorString();
            return result;
        }
        if (written != name)
            for (const QString &form : {"(%1)", "(<%1>)", "(images/%1)", "(<images/%1>)"})
                result.slide.replace(form.arg(name), form.arg(written));
    }
    return result;
}

SlideFiles addPictureToSlide(const QString &baseDir, const QString &slide, const ImageReply &image,
                             const QString &hint) {
    SlideFiles result{slide, {}};
    const QDir folder(baseDir + "/images");
    if (!QDir().mkpath(folder.path())) {
        result.error = "Could not create " + folder.path();
        return result;
    }
    const QString name = uniqueName(folder, slugify(hint).left(40) + "." + image.extension);
    QSaveFile file(folder.filePath(name));
    if (!file.open(QIODevice::WriteOnly) || file.write(image.bytes) < 0 || !file.commit()) {
        result.error = file.fileName() + ": " + file.errorString();
        return result;
    }
    const bool hasText = !parseMedia(slide, baseDir).text.trimmed().isEmpty();
    result.slide = withMedia(slide, QString("![%1](%2)").arg(hasText ? "right" : "", name));
    return result;
}

Generator::Generator(QObject *parent)
    : QObject(parent), m_config(loadAiConfig()), m_network(new QNetworkAccessManager(this)) {
    m_ticker.setInterval(1000);
    connect(&m_ticker, &QTimer::timeout, this, [this] {
        setStatus(QString("%1… %2s (this can take a minute)").arg(m_waiting).arg(m_elapsed.elapsed() / 1000));
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
void Generator::setImageEndpoint(const QString &value) { m_config.imageEndpoint = value.trimmed(); emit configChanged(); }
void Generator::setImageModel(const QString &value) { m_config.imageModel = value.trimmed(); emit configChanged(); }
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

QString Generator::failureText(const QString &parsedError, const QByteArray &body, int http,
                               const QString &networkError) const {
    if (body.isEmpty()) return networkError;
    return (http >= 400 ? QString("HTTP %1: ").arg(http) : QString()) + parsedError;
}

void Generator::begin(const QString &endpoint, const QString &model, const QByteArray &body, const Done &done,
                      const QString &waiting) {
    const QUrl url(endpoint);
    if (!url.isValid() || (url.scheme() != "https" && url.scheme() != "http") || url.host().isEmpty())
        return fail("The endpoint must be an http(s) URL, such as " + QString(DefaultAiEndpoint));
    if (model.isEmpty()) return fail("Choose a model.");
    const QString key = aiApiKey(m_config);
    if (key.isEmpty() && !isLocalHost(url))
        return fail("No API key. Set " + (m_config.keyEnv.isEmpty() ? QString("HYPE_AI_KEY") : m_config.keyEnv) +
                    " in the environment" + (keychainAvailable() ? ", or save one to the Keychain." : "."));
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    if (!key.isEmpty()) request.setRawHeader("Authorization", "Bearer " + key.toUtf8());
    request.setRawHeader("X-Title", "Hype");
    request.setTransferTimeout(RequestTimeoutMs);
    QNetworkReply *reply = m_network->post(request, body);
    m_reply = reply;
    m_waiting = waiting;
    m_elapsed.start();
    m_ticker.start();
    setStatus(waiting + "…");
    connect(reply, &QNetworkReply::finished, this, [this, reply, done] {
        reply->deleteLater();
        m_reply.clear();
        m_ticker.stop();
        emit busyChanged();
        if (reply->error() == QNetworkReply::OperationCanceledError)
            return setStatus("Cancelled");
        done(reply->readAll(), reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(),
             reply->errorString());
    });
    emit busyChanged();
}

void Generator::generate(const QString &prompt, const QString &theme, const QString &directory,
                         const QString &mode) {
    if (busy()) return;
    if (prompt.trimmed().isEmpty())
        return fail(mode == "mindmap" ? "Paste your mind map first." : "Describe the presentation you want.");
    QString error;
    const QString system = promptTemplate(m_config, &error, mode);
    if (system.isEmpty()) return fail("Could not read the prompt template. " + error);
    begin(m_config.endpoint, m_config.model, buildChatRequest(m_config.model, system, prompt.trimmed()),
          [this, theme, directory](const QByteArray &body, int http, const QString &networkError) {
              finishPresentation(body, http, networkError, theme, directory);
          });
}

void Generator::finishPresentation(const QByteArray &body, int http, const QString &networkError,
                                   const QString &theme, const QString &directory) {
    const ChatReply parsed = parseChatReply(body);
    if (!parsed.error.isEmpty()) return fail(failureText(parsed.error, body, http, networkError));
    const GeneratedFiles files = parseGeneratedFiles(parsed.content);
    if (!files.error.isEmpty()) return fail(files.error);
    const Written written = writePresentation(files, directory, outputRoot(), theme);
    if (!written.error.isEmpty()) return fail(written.error);
    setStatus("Created " + written.presentation);
    emit succeeded(written.presentation, written.warnings);
}

void Generator::editSlide(const QString &instruction, const QString &kind, const QString &slide,
                          const QString &outline, int index, const QString &baseDir) {
    if (busy()) return;
    if (instruction.trimmed().isEmpty()) return fail("Say what to change on this slide.");
    if (kind != "text" && kind != "diagram" && kind != "image") return fail("Unknown kind of change: " + kind);
    if (kind != "text" && baseDir.isEmpty())
        return fail("Save the presentation first (Ctrl+S), so the picture has a folder to go in.");
    auto done = [this, kind, slide, baseDir, instruction](const QByteArray &body, int http, const QString &networkError) {
        if (kind == "image") {
            const ImageReply image = parseImageReply(body);
            if (!image.error.isEmpty()) return fail(failureText(image.error, body, http, networkError));
            const SlideFiles added = addPictureToSlide(baseDir, slide, image, instruction);
            if (!added.error.isEmpty()) return fail(added.error);
            setStatus("Added a picture");
            return emit slideReady(added.slide, slideProblems(added.slide, baseDir), "Added a picture");
        }
        finishSlide(body, http, networkError, kind, slide, baseDir);
    };
    if (kind == "image") {
        const QString endpoint = m_config.imageEndpoint.isEmpty() ? m_config.endpoint : m_config.imageEndpoint;
        return begin(endpoint, m_config.imageModel,
                     buildImageRequest(QUrl(endpoint), m_config.imageModel, imagePrompt(instruction, slide)), done,
                     "Drawing");
    }
    QString error;
    const QString system = slideTemplate(kind, &error);
    if (system.isEmpty()) return fail("Could not read the slide template. " + error);
    begin(m_config.endpoint, m_config.model,
          buildChatRequest(m_config.model, system, slideRequest(instruction, slide, outline, index)), done,
          "Rewriting");
}

void Generator::finishSlide(const QByteArray &body, int http, const QString &networkError, const QString &kind,
                            const QString &, const QString &baseDir) {
    const ChatReply parsed = parseChatReply(body);
    if (!parsed.error.isEmpty()) return fail(failureText(parsed.error, body, http, networkError));
    const SlideReply reply = parseSlideReply(parsed.content, kind == "diagram");
    if (!reply.error.isEmpty()) return fail(reply.error);
    QString slide = reply.slide;
    if (!reply.images.isEmpty()) {
        const SlideFiles written = writeSlidePictures(baseDir, reply);
        if (!written.error.isEmpty()) return fail(written.error);
        slide = written.slide;
    }
    const QString summary = reply.images.isEmpty() ? "Rewrote the slide"
                                                   : QString("Rewrote the slide and drew %1 picture%2")
                                                         .arg(reply.images.size()).arg(reply.images.size() > 1 ? "s" : "");
    setStatus(summary);
    emit slideReady(slide, baseDir.isEmpty() ? QStringList() : slideProblems(slide, baseDir), summary);
}
