/****************************************************************************
**
** Copyright (C) 2012 Digia Plc and/or its subsidiary(-ies).
** Contact: http://www.qt-project.org/legal
**
** This file is part of the QtGui module of the Qt Toolkit.
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
#include "qwindowsysteminterface.h"
#include <qpa/qplatformwindow.h>
#include "qwindowsysteminterface_p.h"
#include "private/qguiapplication_p.h"
#include "private/qevent_p.h"
#include "private/qtouchdevice_p.h"
#include <QAbstractEventDispatcher>
#include <qpa/qplatformdrag.h>
#include <qdebug.h>
#include "qemulatedhidpi_p.h"

QT_BEGIN_NAMESPACE


QElapsedTimer QWindowSystemInterfacePrivate::eventTime;

//------------------------------------------------------------
//
// Callback functions for plugins:
//

QWindowSystemInterfacePrivate::WindowSystemEventList QWindowSystemInterfacePrivate::windowSystemEventQueue;

extern QPointer<QWindow> qt_last_mouse_receiver;

/*!
    \class QWindowSystemInterface
    \since 5.0
    \internal
    \preliminary
    \ingroup qpa
    \brief The QWindowSystemInterface provides an event queue for the QPA platform.

    The platform plugins call the various functions to notify about events. The events are queued
    until sendWindowSystemEvents() is called by the event dispatcher.
*/

void QWindowSystemInterface::handleEnterEvent(QWindow *tlw)
{
    if (tlw) {
        QWindowSystemInterfacePrivate::EnterEvent *e = new QWindowSystemInterfacePrivate::EnterEvent(tlw);
        QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
    }
}

void QWindowSystemInterface::handleLeaveEvent(QWindow *tlw)
{
    QWindowSystemInterfacePrivate::LeaveEvent *e = new QWindowSystemInterfacePrivate::LeaveEvent(tlw);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleWindowActivated(QWindow *tlw)
{
    QWindowSystemInterfacePrivate::ActivatedWindowEvent *e = new QWindowSystemInterfacePrivate::ActivatedWindowEvent(tlw);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleWindowStateChanged(QWindow *tlw, Qt::WindowState newState)
{
    QWindowSystemInterfacePrivate::WindowStateChangedEvent *e =
        new QWindowSystemInterfacePrivate::WindowStateChangedEvent(tlw, newState);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleGeometryChange(QWindow *tlw, const QRect &newRect)
{
    QWindowSystemInterfacePrivate::GeometryChangeEvent *e = new QWindowSystemInterfacePrivate::GeometryChangeEvent(tlw, qhidpiPixelToPoint(newRect));
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleSynchronousGeometryChange(QWindow *tlw, const QRect &newRect)
{
    handleGeometryChange(tlw, newRect);
    QWindowSystemInterface::flushWindowSystemEvents();
}

void QWindowSystemInterface::handleCloseEvent(QWindow *tlw)
{
    if (tlw) {
        QWindowSystemInterfacePrivate::CloseEvent *e =
                new QWindowSystemInterfacePrivate::CloseEvent(tlw);
        QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
    }
}

void QWindowSystemInterface::handleSynchronousCloseEvent(QWindow *tlw)
{
    if (tlw) {
        handleCloseEvent(tlw);
        QWindowSystemInterface::flushWindowSystemEvents();
    }
}

/*!

\a w == 0 means that the event is in global coords only, \a local will be ignored in this case

*/
void QWindowSystemInterface::handleMouseEvent(QWindow *w, const QPointF & local, const QPointF & global, Qt::MouseButtons b, Qt::KeyboardModifiers mods)
{
    unsigned long time = QWindowSystemInterfacePrivate::eventTime.elapsed();
    handleMouseEvent(w, time, local, global, b, mods);
}

void QWindowSystemInterface::handleMouseEvent(QWindow *w, ulong timestamp, const QPointF & local, const QPointF & global, Qt::MouseButtons b, Qt::KeyboardModifiers mods)
{
    QWindowSystemInterfacePrivate::MouseEvent * e =
            new QWindowSystemInterfacePrivate::MouseEvent(w, timestamp, qhidpiPixelToPoint(local), qhidpiPixelToPoint(global), b, mods);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleFrameStrutMouseEvent(QWindow *w, const QPointF & local, const QPointF & global, Qt::MouseButtons b, Qt::KeyboardModifiers mods)
{
    const unsigned long time = QWindowSystemInterfacePrivate::eventTime.elapsed();
    handleFrameStrutMouseEvent(w, time, local, global, b, mods);
}

void QWindowSystemInterface::handleFrameStrutMouseEvent(QWindow *w, ulong timestamp, const QPointF & local, const QPointF & global, Qt::MouseButtons b, Qt::KeyboardModifiers mods)
{
    QWindowSystemInterfacePrivate::MouseEvent * e =
            new QWindowSystemInterfacePrivate::MouseEvent(w, timestamp,
                                                          QWindowSystemInterfacePrivate::FrameStrutMouse,
                                                          qhidpiPixelToPoint(local), qhidpiPixelToPoint(global), b, mods);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

bool QWindowSystemInterface::tryHandleSynchronousShortcutEvent(QWindow *w, int k, Qt::KeyboardModifiers mods,
                                                               const QString & text, bool autorep, ushort count)
{
    unsigned long timestamp = QWindowSystemInterfacePrivate::eventTime.elapsed();
    return tryHandleSynchronousShortcutEvent(w, timestamp, k, mods, text, autorep, count);
}

bool QWindowSystemInterface::tryHandleSynchronousShortcutEvent(QWindow *w, ulong timestamp, int k, Qt::KeyboardModifiers mods,
                                                               const QString & text, bool autorep, ushort count)
{
#ifndef QT_NO_SHORTCUT
    QGuiApplicationPrivate::modifier_buttons = mods;

    QKeyEvent qevent(QEvent::ShortcutOverride, k, mods, text, autorep, count);
    qevent.setTimestamp(timestamp);
    return QGuiApplicationPrivate::instance()->shortcutMap.tryShortcutEvent(w, &qevent);
#else
    Q_UNUSED(w)
    Q_UNUSED(timestamp)
    Q_UNUSED(k)
    Q_UNUSED(mods)
    Q_UNUSED(text)
    Q_UNUSED(autorep)
    Q_UNUSED(count)
    return false;
#endif
}

bool QWindowSystemInterface::tryHandleSynchronousExtendedShortcutEvent(QWindow *w, int k, Qt::KeyboardModifiers mods,
                                                                       quint32 nativeScanCode, quint32 nativeVirtualKey, quint32 nativeModifiers,
                                                                       const QString &text, bool autorep, ushort count)
{
    unsigned long timestamp = QWindowSystemInterfacePrivate::eventTime.elapsed();
    return tryHandleSynchronousExtendedShortcutEvent(w, timestamp, k, mods, nativeScanCode, nativeVirtualKey, nativeModifiers, text, autorep, count);
}

bool QWindowSystemInterface::tryHandleSynchronousExtendedShortcutEvent(QWindow *w, ulong timestamp, int k, Qt::KeyboardModifiers mods,
                                                                       quint32 nativeScanCode, quint32 nativeVirtualKey, quint32 nativeModifiers,
                                                                       const QString &text, bool autorep, ushort count)
{
#ifndef QT_NO_SHORTCUT
    QGuiApplicationPrivate::modifier_buttons = mods;

    QKeyEvent qevent(QEvent::ShortcutOverride, k, mods, nativeScanCode, nativeVirtualKey, nativeModifiers, text, autorep, count);
    qevent.setTimestamp(timestamp);
    return QGuiApplicationPrivate::instance()->shortcutMap.tryShortcutEvent(w, &qevent);
#else
    Q_UNUSED(w)
    Q_UNUSED(timestamp)
    Q_UNUSED(k)
    Q_UNUSED(mods)
    Q_UNUSED(nativeScanCode)
    Q_UNUSED(nativeVirtualKey)
    Q_UNUSED(nativeModifiers)
    Q_UNUSED(text)
    Q_UNUSED(autorep)
    Q_UNUSED(count)
    return false;
#endif
}


void QWindowSystemInterface::handleKeyEvent(QWindow *w, QEvent::Type t, int k, Qt::KeyboardModifiers mods, const QString & text, bool autorep, ushort count) {
    unsigned long time = QWindowSystemInterfacePrivate::eventTime.elapsed();
    handleKeyEvent(w, time, t, k, mods, text, autorep, count);
}

void QWindowSystemInterface::handleKeyEvent(QWindow *tlw, ulong timestamp, QEvent::Type t, int k, Qt::KeyboardModifiers mods, const QString & text, bool autorep, ushort count)
{
    QWindowSystemInterfacePrivate::KeyEvent * e =
            new QWindowSystemInterfacePrivate::KeyEvent(tlw, timestamp, t, k, mods, text, autorep, count);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleExtendedKeyEvent(QWindow *w, QEvent::Type type, int key, Qt::KeyboardModifiers modifiers,
                                                    quint32 nativeScanCode, quint32 nativeVirtualKey,
                                                    quint32 nativeModifiers,
                                                    const QString& text, bool autorep,
                                                    ushort count)
{
    unsigned long time = QWindowSystemInterfacePrivate::eventTime.elapsed();
    handleExtendedKeyEvent(w, time, type, key, modifiers, nativeScanCode, nativeVirtualKey, nativeModifiers,
                           text, autorep, count);
}

void QWindowSystemInterface::handleExtendedKeyEvent(QWindow *tlw, ulong timestamp, QEvent::Type type, int key,
                                                    Qt::KeyboardModifiers modifiers,
                                                    quint32 nativeScanCode, quint32 nativeVirtualKey,
                                                    quint32 nativeModifiers,
                                                    const QString& text, bool autorep,
                                                    ushort count)
{
    QWindowSystemInterfacePrivate::KeyEvent * e =
            new QWindowSystemInterfacePrivate::KeyEvent(tlw, timestamp, type, key, modifiers,
                nativeScanCode, nativeVirtualKey, nativeModifiers, text, autorep, count);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleWheelEvent(QWindow *w, const QPointF & local, const QPointF & global, int d, Qt::Orientation o, Qt::KeyboardModifiers mods) {
    unsigned long time = QWindowSystemInterfacePrivate::eventTime.elapsed();
    handleWheelEvent(w, time, local, global, d, o, mods);
}

void QWindowSystemInterface::handleWheelEvent(QWindow *tlw, ulong timestamp, const QPointF & local, const QPointF & global, int d, Qt::Orientation o, Qt::KeyboardModifiers mods)
{
    QPoint point = (o == Qt::Vertical) ? QPoint(0, d) : QPoint(d, 0);
    handleWheelEvent(tlw, timestamp, local, global, QPoint(), point, mods);
}

void QWindowSystemInterface::handleWheelEvent(QWindow *w, const QPointF & local, const QPointF & global, QPoint pixelDelta, QPoint angleDelta, Qt::KeyboardModifiers mods)
{
    unsigned long time = QWindowSystemInterfacePrivate::eventTime.elapsed();
    handleWheelEvent(w, time, local, global, pixelDelta, angleDelta, mods);
}

void QWindowSystemInterface::handleWheelEvent(QWindow *tlw, ulong timestamp, const QPointF & local, const QPointF & global, QPoint pixelDelta, QPoint angleDelta, Qt::KeyboardModifiers mods)
{
    // Qt 4 sends two separate wheel events for horizontal and vertical
    // deltas. For Qt 5 we want to send the deltas in one event, but at the
    // same time preserve source and behavior compatibility with Qt 4.
    //
    // In addition high-resolution pixel-based deltas are also supported.
    // Platforms that does not support these may pass a null point here.
    // Angle deltas must always be sent in addition to pixel deltas.
    QWindowSystemInterfacePrivate::WheelEvent *e;

    if (angleDelta.isNull())
        return;

    // Simple case: vertical deltas only:
    if (angleDelta.y() != 0 && angleDelta.x() == 0) {
        e = new QWindowSystemInterfacePrivate::WheelEvent(tlw, timestamp, qhidpiPixelToPoint(local), qhidpiPixelToPoint(global), pixelDelta, angleDelta, angleDelta.y(), Qt::Vertical, mods);
        QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
        return;
    }

    // Simple case: horizontal deltas only:
    if (angleDelta.y() == 0 && angleDelta.x() != 0) {
        e = new QWindowSystemInterfacePrivate::WheelEvent(tlw, timestamp, qhidpiPixelToPoint(local), qhidpiPixelToPoint(global), pixelDelta, angleDelta, angleDelta.x(), Qt::Horizontal, mods);
        QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
        return;
    }

    // Both horizontal and vertical deltas: Send two wheel events.
    // The first event contains the Qt 5 pixel and angle delta as points,
    // and in addition the Qt 4 compatibility vertical angle delta.
    e = new QWindowSystemInterfacePrivate::WheelEvent(tlw, timestamp, qhidpiPixelToPoint(local), qhidpiPixelToPoint(global), pixelDelta, angleDelta, angleDelta.y(), Qt::Vertical, mods);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);

    // The second event contains null pixel and angle points and the
    // Qt 4 compatibility horizontal angle delta.
    e = new QWindowSystemInterfacePrivate::WheelEvent(tlw, timestamp, qhidpiPixelToPoint(local), qhidpiPixelToPoint(global), QPoint(), QPoint(), angleDelta.x(), Qt::Horizontal, mods);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}


QWindowSystemInterfacePrivate::ExposeEvent::ExposeEvent(QWindow *exposed, const QRegion &region)
    : WindowSystemEvent(Expose)
    , exposed(exposed)
    , isExposed(exposed && exposed->handle() ? exposed->handle()->isExposed() : false)
    , region(region)
{
}

int QWindowSystemInterfacePrivate::windowSystemEventsQueued()
{
    return windowSystemEventQueue.count();
}

QWindowSystemInterfacePrivate::WindowSystemEvent * QWindowSystemInterfacePrivate::getWindowSystemEvent()
{
    return windowSystemEventQueue.takeFirstOrReturnNull();
}

void QWindowSystemInterfacePrivate::queueWindowSystemEvent(QWindowSystemInterfacePrivate::WindowSystemEvent *ev)
{
    windowSystemEventQueue.append(ev);

    QAbstractEventDispatcher *dispatcher = QGuiApplicationPrivate::qt_qpa_core_dispatcher();
    if (dispatcher)
        dispatcher->wakeUp();
}

void QWindowSystemInterface::registerTouchDevice(QTouchDevice *device)
{
    QTouchDevicePrivate::registerDevice(device);
}

void QWindowSystemInterface::handleTouchEvent(QWindow *w, QTouchDevice *device,
                                              const QList<TouchPoint> &points, Qt::KeyboardModifiers mods)
{
    unsigned long time = QWindowSystemInterfacePrivate::eventTime.elapsed();
    handleTouchEvent(w, time, device, points, mods);
}

QList<QTouchEvent::TouchPoint> QWindowSystemInterfacePrivate::convertTouchPoints(const QList<QWindowSystemInterface::TouchPoint> &points, QEvent::Type *type)
{
    QList<QTouchEvent::TouchPoint> touchPoints;
    Qt::TouchPointStates states;
    QTouchEvent::TouchPoint p;

    QList<QWindowSystemInterface::TouchPoint>::const_iterator point = points.constBegin();
    QList<QWindowSystemInterface::TouchPoint>::const_iterator end = points.constEnd();
    while (point != end) {
        p.setId(point->id);
        p.setPressure(point->pressure);
        states |= point->state;
        p.setState(point->state);

        const QPointF screenPos = point->area.center();
        p.setScreenPos(qhidpiPixelToPoint(screenPos));
        p.setScreenRect(qhidpiPixelToPoint(point->area));

        // The local pos and rect are not set, they will be calculated
        // when the event gets processed by QGuiApplication.

        p.setNormalizedPos(qhidpiPixelToPoint(point->normalPosition));
        p.setVelocity(qhidpiPixelToPoint(point->velocity));
        p.setFlags(point->flags);
        p.setRawScreenPositions(qhidpiPixelToPoint(point->rawPositions));

        touchPoints.append(p);
        ++point;
    }

    // Determine the event type based on the combined point states.
    if (type) {
        *type = QEvent::TouchUpdate;
        if (states == Qt::TouchPointPressed)
            *type = QEvent::TouchBegin;
        else if (states == Qt::TouchPointReleased)
            *type = QEvent::TouchEnd;
    }

    return touchPoints;
}

void QWindowSystemInterface::handleTouchEvent(QWindow *tlw, ulong timestamp, QTouchDevice *device,
                                              const QList<TouchPoint> &points, Qt::KeyboardModifiers mods)
{
    if (!points.size()) // Touch events must have at least one point
        return;

    if (!QTouchDevicePrivate::isRegistered(device)) // Disallow passing bogus, non-registered devices.
        return;

    QEvent::Type type;
    QList<QTouchEvent::TouchPoint> touchPoints = QWindowSystemInterfacePrivate::convertTouchPoints(points, &type);

    QWindowSystemInterfacePrivate::TouchEvent *e =
            new QWindowSystemInterfacePrivate::TouchEvent(tlw, timestamp, type, device, touchPoints, mods);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleTouchCancelEvent(QWindow *w, QTouchDevice *device,
                                                    Qt::KeyboardModifiers mods)
{
    unsigned long time = QWindowSystemInterfacePrivate::eventTime.elapsed();
    handleTouchCancelEvent(w, time, device, mods);
}

void QWindowSystemInterface::handleTouchCancelEvent(QWindow *w, ulong timestamp, QTouchDevice *device,
                                                    Qt::KeyboardModifiers mods)
{
    QWindowSystemInterfacePrivate::TouchEvent *e =
            new QWindowSystemInterfacePrivate::TouchEvent(w, timestamp, QEvent::TouchCancel, device,
                                                         QList<QTouchEvent::TouchPoint>(), mods);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleScreenOrientationChange(QScreen *screen, Qt::ScreenOrientation orientation)
{
    QWindowSystemInterfacePrivate::ScreenOrientationEvent *e =
            new QWindowSystemInterfacePrivate::ScreenOrientationEvent(screen, orientation);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleScreenGeometryChange(QScreen *screen, const QRect &geometry)
{
    QWindowSystemInterfacePrivate::ScreenGeometryEvent *e =
            new QWindowSystemInterfacePrivate::ScreenGeometryEvent(screen, qhidpiPixelToPoint(geometry));
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleScreenAvailableGeometryChange(QScreen *screen, const QRect &availableGeometry)
{
    QWindowSystemInterfacePrivate::ScreenAvailableGeometryEvent *e =
            new QWindowSystemInterfacePrivate::ScreenAvailableGeometryEvent(screen, qhidpiPixelToPoint(availableGeometry));
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleScreenLogicalDotsPerInchChange(QScreen *screen, qreal dpiX, qreal dpiY)
{
    QWindowSystemInterfacePrivate::ScreenLogicalDotsPerInchEvent *e =
            new QWindowSystemInterfacePrivate::ScreenLogicalDotsPerInchEvent(screen, dpiX, dpiY); // ### tja
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleScreenRefreshRateChange(QScreen *screen, qreal newRefreshRate)
{
    QWindowSystemInterfacePrivate::ScreenRefreshRateEvent *e =
            new QWindowSystemInterfacePrivate::ScreenRefreshRateEvent(screen, newRefreshRate);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleThemeChange(QWindow *tlw)
{
    QWindowSystemInterfacePrivate::ThemeChangeEvent *e = new QWindowSystemInterfacePrivate::ThemeChangeEvent(tlw);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleExposeEvent(QWindow *tlw, const QRegion &region)
{
    QWindowSystemInterfacePrivate::ExposeEvent *e = new QWindowSystemInterfacePrivate::ExposeEvent(tlw, qhidpiPixelToPoint(region));
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleSynchronousExposeEvent(QWindow *tlw, const QRegion &region)
{
    QWindowSystemInterface::handleExposeEvent(tlw, qhidpiPixelToPoint(region));
    QWindowSystemInterface::flushWindowSystemEvents();
}

void QWindowSystemInterface::flushWindowSystemEvents()
{
    sendWindowSystemEventsImplementation(QEventLoop::AllEvents);
}

bool QWindowSystemInterface::sendWindowSystemEvents(QEventLoop::ProcessEventsFlags flags)
{
    QCoreApplication::sendPostedEvents(); // handle gui and posted events
    return sendWindowSystemEventsImplementation(flags);
}

bool QWindowSystemInterface::sendWindowSystemEventsImplementation(QEventLoop::ProcessEventsFlags flags)
{
    int nevents = 0;

    while (true) {
        QWindowSystemInterfacePrivate::WindowSystemEvent *event;
        if (!(flags & QEventLoop::ExcludeUserInputEvents)
            && QWindowSystemInterfacePrivate::windowSystemEventsQueued() > 0) {
            // process a pending user input event
            event = QWindowSystemInterfacePrivate::getWindowSystemEvent();
            if (!event)
                break;
        } else {
            break;
        }

        nevents++;

        QGuiApplicationPrivate::processWindowSystemEvent(event);
        delete event;
    }

    return (nevents > 0);
}

int QWindowSystemInterface::windowSystemEventsQueued()
{
    return QWindowSystemInterfacePrivate::windowSystemEventsQueued();
}

#ifndef QT_NO_DRAGANDDROP
QPlatformDragQtResponse QWindowSystemInterface::handleDrag(QWindow *w, const QMimeData *dropData, const QPoint &p, Qt::DropActions supportedActions)
{
    return QGuiApplicationPrivate::processDrag(w, dropData, qhidpiPixelToPoint(p),supportedActions);
}

QPlatformDropQtResponse QWindowSystemInterface::handleDrop(QWindow *w, const QMimeData *dropData, const QPoint &p, Qt::DropActions supportedActions)
{
    return QGuiApplicationPrivate::processDrop(w, dropData, qhidpiPixelToPoint(p),supportedActions);
}
#endif // QT_NO_DRAGANDDROP

/*!
    \fn static QWindowSystemInterface::handleNativeEvent(QWindow *window, const QByteArray &eventType, void *message, long *result)
    \brief Passes a native event identified by \a eventType to the \a window.

    \note This function can only be called from the GUI thread.
*/

bool QWindowSystemInterface::handleNativeEvent(QWindow *window, const QByteArray &eventType, void *message, long *result)
{
    return QGuiApplicationPrivate::processNativeEvent(window, eventType, message, result);
}

void QWindowSystemInterface::handleFileOpenEvent(const QString& fileName)
{
    QWindowSystemInterfacePrivate::FileOpenEvent e(fileName);
    QGuiApplicationPrivate::processWindowSystemEvent(&e);
}

void QWindowSystemInterface::handleTabletEvent(QWindow *w, ulong timestamp, bool down, const QPointF &local, const QPointF &global,
                                               int device, int pointerType, qreal pressure, int xTilt, int yTilt,
                                               qreal tangentialPressure, qreal rotation, int z, qint64 uid,
                                               Qt::KeyboardModifiers modifiers)
{
    QWindowSystemInterfacePrivate::TabletEvent *e =
            new QWindowSystemInterfacePrivate::TabletEvent(w, timestamp, down, qhidpiPixelToPoint(local), qhidpiPixelToPoint(global), device, pointerType, pressure,
                                                           xTilt, yTilt, tangentialPressure, rotation, z, uid, modifiers);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleTabletEvent(QWindow *w, bool down, const QPointF &local, const QPointF &global,
                                               int device, int pointerType, qreal pressure, int xTilt, int yTilt,
                                               qreal tangentialPressure, qreal rotation, int z, qint64 uid,
                                               Qt::KeyboardModifiers modifiers)
{
    ulong time = QWindowSystemInterfacePrivate::eventTime.elapsed();
    handleTabletEvent(w, time, down, local, global, device, pointerType, pressure,
                      xTilt, yTilt, tangentialPressure, rotation, z, uid, modifiers);
}

void QWindowSystemInterface::handleTabletEnterProximityEvent(ulong timestamp, int device, int pointerType, qint64 uid)
{
    QWindowSystemInterfacePrivate::TabletEnterProximityEvent *e =
            new QWindowSystemInterfacePrivate::TabletEnterProximityEvent(timestamp, device, pointerType, uid);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleTabletEnterProximityEvent(int device, int pointerType, qint64 uid)
{
    ulong time = QWindowSystemInterfacePrivate::eventTime.elapsed();
    handleTabletEnterProximityEvent(time, device, pointerType, uid);
}

void QWindowSystemInterface::handleTabletLeaveProximityEvent(ulong timestamp, int device, int pointerType, qint64 uid)
{
    QWindowSystemInterfacePrivate::TabletLeaveProximityEvent *e =
            new QWindowSystemInterfacePrivate::TabletLeaveProximityEvent(timestamp, device, pointerType, uid);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

void QWindowSystemInterface::handleTabletLeaveProximityEvent(int device, int pointerType, qint64 uid)
{
    ulong time = QWindowSystemInterfacePrivate::eventTime.elapsed();
    handleTabletLeaveProximityEvent(time, device, pointerType, uid);
}

void QWindowSystemInterface::handlePlatformPanelEvent(QWindow *w)
{
    QWindowSystemInterfacePrivate::PlatformPanelEvent *e =
            new QWindowSystemInterfacePrivate::PlatformPanelEvent(w);
    QWindowSystemInterfacePrivate::queueWindowSystemEvent(e);
}

Q_GUI_EXPORT void qt_handleMouseEvent(QWindow *w, const QPointF & local, const QPointF & global, Qt::MouseButtons b, Qt::KeyboardModifiers mods = Qt::NoModifier) {
    QWindowSystemInterface::handleMouseEvent(w, local, global,  b,  mods);
}

Q_GUI_EXPORT void qt_handleKeyEvent(QWindow *w, QEvent::Type t, int k, Qt::KeyboardModifiers mods, const QString & text = QString(), bool autorep = false, ushort count = 1)
{
    QWindowSystemInterface::handleKeyEvent(w, t, k, mods, text, autorep, count);
}

static QWindowSystemInterface::TouchPoint touchPoint(const QTouchEvent::TouchPoint& pt)
{
    QWindowSystemInterface::TouchPoint p;
    p.id = pt.id();
    p.flags = pt.flags();
    p.normalPosition = pt.normalizedPos();
    p.area = pt.screenRect();
    p.pressure = pt.pressure();
    p.state = pt.state();
    p.velocity = pt.velocity();
    p.rawPositions = pt.rawScreenPositions();
    return p;
}
static QList<struct QWindowSystemInterface::TouchPoint> touchPointList(const QList<QTouchEvent::TouchPoint>& pointList)
{
    QList<struct QWindowSystemInterface::TouchPoint> newList;

    Q_FOREACH (QTouchEvent::TouchPoint p, pointList)
    {
        newList.append(touchPoint(p));
    }
    return newList;
}

Q_GUI_EXPORT  void qt_handleTouchEvent(QWindow *w, QTouchDevice *device,
                                const QList<QTouchEvent::TouchPoint> &points,
                                Qt::KeyboardModifiers mods = Qt::NoModifier)
{
    QWindowSystemInterface::handleTouchEvent(w, device, touchPointList(points), mods);
}

QT_END_NAMESPACE
