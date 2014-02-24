/****************************************************************************
**
** Copyright (C) 2013 Digia Plc and/or its subsidiary(-ies).
** Contact: http://www.qt-project.org/legal
**
** This file is part of the plugins of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:LGPL$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and Digia.  For licensing terms and
** conditions see http://qt.digia.com/licensing.  For further information
** use the contact form at http://qt.digia.com/contact-us.
**
** GNU Lesser General Public License Usage
** Alternatively, this file may be used under the terms of the GNU Lesser
** General Public License version 2.1 as published by the Free Software
** Foundation and appearing in the file LICENSE.LGPL included in the
** packaging of this file.  Please review the following information to
** ensure the GNU Lesser General Public License version 2.1 requirements
** will be met: http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
**
** In addition, as a special exception, Digia gives you certain additional
** rights.  These rights are described in the Digia Qt LGPL Exception
** version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 3.0 as published by the Free Software
** Foundation and appearing in the file LICENSE.GPL included in the
** packaging of this file.  Please review the following information to
** ensure the GNU General Public License version 3.0 requirements will be
** met: http://www.gnu.org/copyleft/gpl.html.
**
**
** $QT_END_LICENSE$
**
****************************************************************************/

#include "qcocoamimetypes.h"
#include "qmacmime.h"
#include "qcocoahelpers.h"

QT_BEGIN_NAMESPACE

class QMacPasteboardMimeTiff : public QMacInternalPasteboardMime {
public:
    QMacPasteboardMimeTiff() : QMacInternalPasteboardMime(MIME_ALL) { }
    QString convertorName();

    QString flavorFor(const QString &mime);
    QString mimeFor(QString flav);
    bool canConvert(const QString &mime, QString flav);
    QVariant convertToMime(const QString &mime, QList<QByteArray> data, QString flav);
    QList<QByteArray> convertFromMime(const QString &mime, QVariant data, QString flav);
};

QString QMacPasteboardMimeTiff::convertorName()
{
    return QLatin1String("Tiff");
}

QString QMacPasteboardMimeTiff::flavorFor(const QString &mime)
{
    if (mime.startsWith(QLatin1String("application/x-qt-image")))
        return QLatin1String("public.tiff");
    return QString();
}

QString QMacPasteboardMimeTiff::mimeFor(QString flav)
{
    if (flav == QLatin1String("public.tiff"))
        return QLatin1String("application/x-qt-image");
    return QString();
}

bool QMacPasteboardMimeTiff::canConvert(const QString &mime, QString flav)
{
    return flav == QLatin1String("public.tiff") && mime == QLatin1String("application/x-qt-image");
}

QVariant QMacPasteboardMimeTiff::convertToMime(const QString &mime, QList<QByteArray> data, QString flav)
{
    if (data.count() > 1)
        qWarning("QMacPasteboardMimeTiff: Cannot handle multiple member data");
    QVariant ret;
    if (!canConvert(mime, flav))
        return ret;
    const QByteArray &a = data.first();
    QCFType<CGImageRef> image;
    QCFType<CFDataRef> tiffData = CFDataCreateWithBytesNoCopy(0,
                                                reinterpret_cast<const UInt8 *>(a.constData()),
                                                a.size(), kCFAllocatorNull);
    QCFType<CGImageSourceRef> imageSource = CGImageSourceCreateWithData(tiffData, 0);
    image = CGImageSourceCreateImageAtIndex(imageSource, 0, 0);
    if (image != 0)
        ret = QVariant(qt_mac_toQImage(image));
    return ret;
}

QList<QByteArray> QMacPasteboardMimeTiff::convertFromMime(const QString &mime, QVariant variant, QString flav)
{
    QList<QByteArray> ret;
    if (!canConvert(mime, flav))
        return ret;

    QImage img = qvariant_cast<QImage>(variant);
    QCFType<CGImageRef> cgimage = qt_mac_image_to_cgimage(img);

    QCFType<CFMutableDataRef> data = CFDataCreateMutable(0, 0);
    QCFType<CGImageDestinationRef> imageDestination = CGImageDestinationCreateWithData(data, kUTTypeTIFF, 1, 0);
    if (imageDestination != 0) {
        CFTypeRef keys[2];
        QCFType<CFTypeRef> values[2];
        QCFType<CFDictionaryRef> options;
        keys[0] = kCGImagePropertyPixelWidth;
        keys[1] = kCGImagePropertyPixelHeight;
        int width = img.width();
        int height = img.height();
        values[0] = CFNumberCreate(0, kCFNumberIntType, &width);
        values[1] = CFNumberCreate(0, kCFNumberIntType, &height);
        options = CFDictionaryCreate(0, reinterpret_cast<const void **>(keys),
                                     reinterpret_cast<const void **>(values), 2,
                                     &kCFTypeDictionaryKeyCallBacks,
                                     &kCFTypeDictionaryValueCallBacks);
        CGImageDestinationAddImage(imageDestination, cgimage, options);
        CGImageDestinationFinalize(imageDestination);
    }
    QByteArray ar(CFDataGetLength(data), 0);
    CFDataGetBytes(data,
            CFRangeMake(0, ar.size()),
            reinterpret_cast<UInt8 *>(ar.data()));
    ret.append(ar);
    return ret;
}

void QCocoaMimeTypes::initializeMimeTypes()
{
    new QMacPasteboardMimeTiff;
}

QT_END_NAMESPACE
