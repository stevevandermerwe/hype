#include "html.h"
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

bool writeHtml(const QString &directory, const QString &path, QString *error) {
    QFile manifest(directory + "/slides.json");
    if (!manifest.open(QIODevice::ReadOnly)) {
        if (error) *error = manifest.errorString();
        return false;
    }
    const QJsonObject root = QJsonDocument::fromJson(manifest.readAll()).object();
    const QString title = root.value("title").toString();
    QJsonArray slides;
    int number = 1;
    for (const auto &value : root.value("slides").toArray()) {
        const QString image = value.toObject().value("image").toString();
        QFile file(directory + "/" + image);
        if (!file.open(QIODevice::ReadOnly)) {
            if (error) *error = QString("Could not read %1: %2").arg(image, file.errorString());
            return false;
        }
        const QString uri = QStringLiteral("data:image/png;base64,") +
                            QString::fromLatin1(file.readAll().toBase64());
        slides.append(QJsonObject{{"src", uri}, {"n", number++}});
    }

    QString html;
    html += R"HTML(<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>)HTML";
    html += title.toHtmlEscaped();
    html += R"HTML(</title>
<style>
  :root { --bg:#0b0a14; --fg:#e9e6f8; --dim:#8a86a8; }
  * { box-sizing:border-box; }
  html, body { margin:0; height:100%; background:var(--bg); color:var(--fg); overflow:hidden;
    font-family:-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
  #stage { position:fixed; inset:0; display:flex; align-items:center; justify-content:center; cursor:pointer; }
  #slide { max-width:100%; max-height:100%; object-fit:contain;
    box-shadow:0 10px 70px rgba(0,0,0,.55); user-select:none; -webkit-user-select:none; }
  #counter { position:fixed; right:18px; bottom:12px; font-size:13px; color:var(--dim);
    font-variant-numeric:tabular-nums; }
  #progress { position:fixed; left:0; bottom:0; height:3px; background:var(--fg); opacity:.28;
    width:0; transition:width .18s ease; }
  #hint { position:fixed; left:16px; bottom:12px; font-size:12px; color:var(--dim); opacity:.75; }
  #overview { position:fixed; inset:0; background:rgba(8,7,16,.97); display:none; flex-wrap:wrap;
    gap:18px; padding:28px; overflow:auto; align-content:flex-start; }
  #overview .thumb { width:calc(25% - 14px); cursor:pointer; border:2px solid rgba(255,255,255,.08);
    border-radius:5px; overflow:hidden; background:#000; transition:border-color .15s; }
  #overview .thumb:hover { border-color:rgba(255,255,255,.35); }
  #overview .thumb.current { border-color:var(--fg); }
  #overview .thumb img { width:100%; display:block; }
  #overview .num { font-size:12px; color:var(--dim); padding:6px 8px; }
  @media (max-width:700px) { #overview .thumb { width:calc(50% - 9px); } }
</style>
</head>
<body>
  <div id="stage"><img id="slide" alt=""></div>
  <div id="counter"></div>
  <div id="progress"></div>
  <div id="hint">← → navigate · F fullscreen · G overview</div>
  <div id="overview"></div>
<script>
const slides = )HTML";
    html += QString::fromUtf8(QJsonDocument(slides).toJson(QJsonDocument::Compact));
    html += R"HTML(;
let current = 0;
const img = document.getElementById('slide');
const counter = document.getElementById('counter');
const progress = document.getElementById('progress');
const overview = document.getElementById('overview');
const stage = document.getElementById('stage');

slides.forEach(function (s, i) {
  const cell = document.createElement('div');
  cell.className = 'thumb';
  const pic = document.createElement('img');
  pic.src = s.src;
  pic.alt = 'Slide ' + (i + 1);
  pic.loading = 'lazy';
  const num = document.createElement('div');
  num.className = 'num';
  num.textContent = (i + 1) + ' / ' + slides.length;
  cell.appendChild(pic);
  cell.appendChild(num);
  cell.addEventListener('click', function () { go(i); setOverview(false); });
  overview.appendChild(cell);
});

function render() {
  img.src = slides[current].src;
  img.alt = 'Slide ' + (current + 1);
  counter.textContent = (current + 1) + ' / ' + slides.length;
  progress.style.width = ((current + 1) / slides.length * 100) + '%';
  for (let k = 0; k < overview.children.length; k++)
    overview.children[k].classList.toggle('current', k === current);
}

function go(n) {
  if (!slides.length) return;
  current = ((n % slides.length) + slides.length) % slides.length;
  render();
}

function setOverview(open) {
  overview.style.display = open ? 'flex' : 'none';
  if (open) {
    const cur = overview.children[current];
    if (cur && cur.scrollIntoView) cur.scrollIntoView({ block: 'nearest' });
  }
}

function toggleFullscreen() {
  if (document.fullscreenElement) document.exitFullscreen();
  else if (document.documentElement.requestFullscreen) document.documentElement.requestFullscreen();
}

document.addEventListener('keydown', function (e) {
  if (overview.style.display === 'flex') {
    if (e.key === 'Escape' || e.key === 'g' || e.key === 'G' || e.key === 'o' || e.key === 'O') {
      setOverview(false); e.preventDefault();
    }
    return;
  }
  switch (e.key) {
    case 'ArrowRight': case 'ArrowDown': case ' ': case 'PageDown': case 'Enter':
      go(current + 1); e.preventDefault(); break;
    case 'ArrowLeft': case 'ArrowUp': case 'Backspace': case 'PageUp':
      go(current - 1); e.preventDefault(); break;
    case 'Home': go(0); e.preventDefault(); break;
    case 'End': go(slides.length - 1); e.preventDefault(); break;
    case 'f': case 'F': toggleFullscreen(); break;
    case 'g': case 'G': case 'o': case 'O': setOverview(true); break;
    case 'Escape': if (document.fullscreenElement) document.exitFullscreen(); break;
  }
});

stage.addEventListener('click', function () { go(current + 1); });

let touchX = 0, touchY = 0;
document.addEventListener('touchstart', function (e) {
  touchX = e.touches[0].clientX; touchY = e.touches[0].clientY;
}, { passive: true });
document.addEventListener('touchend', function (e) {
  const dx = e.changedTouches[0].clientX - touchX;
  const dy = e.changedTouches[0].clientY - touchY;
  if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) { if (dx < 0) go(current + 1); else go(current - 1); }
}, { passive: true });

render();
</script>
</body>
</html>
)HTML";

    QSaveFile out(path);
    if (!out.open(QIODevice::WriteOnly)) {
        if (error) *error = out.errorString();
        return false;
    }
    out.write(html.toUtf8());
    if (!out.commit()) {
        if (error) *error = out.errorString();
        return false;
    }
    return true;
}
