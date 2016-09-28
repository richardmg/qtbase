TARGET = qiosnsphotolibrarysupport

PLUGIN_CLASS_NAME = QIosOptionalPlugin_NSPhotoLibrary
PLUGIN_EXTENDS = -
PLUGIN_TYPE = platforms/darwin

load(qt_plugin)

QT += core gui gui-private
LIBS += -framework UIKit -framework AssetsLibrary

HEADERS = \
        qiosfileengineassetslibrary.h \
        qiosfileenginefactory.h \
        qiosimagepickercontroller.h

OBJECTIVE_SOURCES = \
        plugin.mm \
        qiosfileengineassetslibrary.mm \
        qiosimagepickercontroller.mm \

OTHER_FILES = \
        plugin.json

