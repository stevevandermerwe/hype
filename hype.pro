QT += core gui qml quick quickcontrols2 multimedia concurrent dbus
# macOS has no freedesktop portal; filedialog.cpp falls back to QFileDialog there.
macx: QT += widgets
# Like Qt's own modules, Hype never throws or catches. Without unwinding tables and with
# link-time optimization, the installed binary is about a quarter smaller.
CONFIG += c++17 release ltcg exceptions_off
TARGET = hype
TEMPLATE = app
HEADERS += src/deck.h src/renderer.h src/markdown.h
SOURCES += src/main.cpp src/deck.cpp src/renderer.cpp src/markdown.cpp
RESOURCES += src/resources.qrc

SOURCES += src/syntax.cpp
HEADERS += src/syntax.h
SOURCES += src/pptx.cpp
HEADERS += src/pptx.h
SOURCES += src/html.cpp
HEADERS += src/html.h
SOURCES += src/exporter.cpp
HEADERS += src/exporter.h
SOURCES += src/themepreview.cpp
HEADERS += src/themepreview.h
LIBS += -lz -lwebpdemux -lwebp

SOURCES += src/animationexport.cpp
HEADERS += src/animationexport.h

SOURCES += src/apptheme.cpp
HEADERS += src/apptheme.h
SOURCES += src/themecatalog.cpp
HEADERS += src/themecatalog.h
SOURCES += src/assetstore.cpp
HEADERS += src/assetstore.h
SOURCES += src/images.cpp
HEADERS += src/images.h
SOURCES += src/filedialog.cpp
HEADERS += src/filedialog.h
SOURCES += src/recovery.cpp
HEADERS += src/recovery.h
SOURCES += src/cli.cpp
HEADERS += src/cli.h
