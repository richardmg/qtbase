/****************************************************************************
**
** Copyright (C) 2012 Digia Plc and/or its subsidiary(-ies).
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

#include "qcocoabackingstore.h"
#include "qcocoaautoreleasepool.h"
#include "qcocoahelpers.h"

#include <QtCore/qdebug.h>
#include <QtGui/QPainter>

QT_BEGIN_NAMESPACE

QCocoaBackingStore::QCocoaBackingStore(QWindow *window)
    : QPlatformBackingStore(window)
    , m_cgImage(0)
{
}

QCocoaBackingStore::~QCocoaBackingStore()
{
    CGImageRelease(m_cgImage);
}

QPaintDevice *QCocoaBackingStore::paintDevice()
{
    if (m_qImage.size() != m_requestedSize) {
        CGImageRelease(m_cgImage);
        m_qImage = QImage(m_requestedSize, QImage::Format_ARGB32_Premultiplied);
        m_cgImage = qt_mac_toCGImage(m_qImage, false, 0);
    }
    return &m_qImage;
}

void QCocoaBackingStore::flush(QWindow *win, const QRegion &region, const QPoint &offset)
{
    Q_UNUSED(offset);
    QCocoaAutoReleasePool pool;

    QCocoaWindow *cocoaWindow = static_cast<QCocoaWindow *>(win->handle());
    if (cocoaWindow) {
        QRect geo = region.boundingRect();
        NSRect rect = NSMakeRect(geo.x(), geo.y(), geo.width(), geo.height());
        [cocoaWindow->m_contentView setBackingStoreCGImage:m_cgImage offset:offset];
        [cocoaWindow->m_contentView displayRect:rect];
   }
}

void QCocoaBackingStore::resize(const QSize &size, const QRegion &)
{
    m_requestedSize = size;
}

bool QCocoaBackingStore::scroll(const QRegion &area, int dx, int dy)
{
    extern void qt_scrollRectInImage(QImage &img, const QRect &rect, const QPoint &offset);
    QPoint qpoint(dx, dy);
    const QVector<QRect> qrects = area.rects();
    for (int i = 0; i < qrects.count(); ++i) {
        const QRect &qrect = qrects.at(i);
        qt_scrollRectInImage(m_qImage, qrect, qpoint);
    }
    return true;
}

QT_END_NAMESPACE
