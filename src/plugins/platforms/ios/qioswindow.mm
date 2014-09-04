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

#include "qioswindow.h"

#include "qiosapplicationdelegate.h"
#include "qioscontext.h"
#include "qiosglobal.h"
#include "qiosintegration.h"
#include "qiosscreen.h"
#include "qiosviewcontroller.h"
#include "quiview.h"

#include <QtGui/private/qwindow_p.h>
#include <qpa/qplatformintegration.h>

#import <QuartzCore/CAEAGLLayer.h>

#include <QtDebug>

QIOSWindow::QIOSWindow(QWindow *window)
    : QPlatformWindow(window)
    , m_view([[QUIView alloc] initWithQIOSWindow:this])
    , m_windowLevel(0)
{
    connect(qGuiApp, &QGuiApplication::applicationStateChanged, this, &QIOSWindow::applicationStateChanged);

    setParent(QPlatformWindow::parent());

    // Resolve default window geometry in case it was not set before creating the
    // platform window. This picks up eg. minimum-size if set, and defaults to
    // the "maxmized" geometry (even though we're not in that window state).
    // FIXME: Detect if we apply a maximized geometry and send a window state
    // change event in that case.
    m_normalGeometry = initialGeometry(window, QPlatformWindow::geometry(),
        screen()->availableGeometry().width(), screen()->availableGeometry().height());

    setWindowState(window->windowState());
    setOpacity(window->opacity());
}

QIOSWindow::~QIOSWindow()
{
    // According to the UIResponder documentation, Cocoa Touch should react to system interruptions
    // that "might cause the view to be removed from the window" by sending touchesCancelled, but in
    // practice this doesn't seem to happen when removing the view from its superview. To ensure that
    // Qt's internal state for touch and mouse handling is kept consistent, we therefor have to force
    // cancellation of all touch events.
    [m_view touchesCancelled:0 withEvent:0];

    clearAccessibleCache();
    m_view->m_qioswindow = 0;
    [m_view removeFromSuperview];
    [m_view release];
}

bool QIOSWindow::blockedByModal()
{
    QWindow *modalWindow = QGuiApplication::modalWindow();
    return modalWindow && modalWindow != window();
}

void QIOSWindow::setVisible(bool visible)
{
    m_view.hidden = !visible;
    [m_view setNeedsDisplay];

    if (!isQtApplication() || !window()->isTopLevel())
        return;

    // Since iOS doesn't do window management the way a Qt application
    // expects, we need to raise and activate windows ourselves:
    if (visible)
        updateWindowLevel();

    if (blockedByModal()) {
        if (visible)
            raise();
        return;
    }

    if (visible) {
        requestActivateWindow();
        static_cast<QIOSScreen *>(screen())->updateStatusBarVisibility();
    } else {
        // Activate top-most visible QWindow:
        NSArray *subviews = m_view.viewController.view.subviews;
        for (int i = int(subviews.count) - 1; i >= 0; --i) {
            UIView *view = [subviews objectAtIndex:i];
            if (!view.hidden) {
                QWindow *w = view.qwindow;
                if (w && w->isTopLevel()) {
                    static_cast<QIOSWindow *>(w->handle())->requestActivateWindow();
                    break;
                }
            }
        }
    }
}

void QIOSWindow::setOpacity(qreal level)
{
    m_view.alpha = qBound(0.0, level, 1.0);
}

void QIOSWindow::setGeometry(const QRect &rect)
{
    m_normalGeometry = rect;

    if (window()->windowState() != Qt::WindowNoState) {
        QPlatformWindow::setGeometry(rect);

        // The layout will realize the requested geometry was not applied, and
        // send geometry-change events that match the actual geometry.
        [m_view setNeedsLayout];

        if (window()->inherits("QWidgetWindow")) {
            // QWidget wrongly assumes that setGeometry resets the window
            // state back to Qt::NoWindowState, so we need to inform it that
            // that his is not the case by re-issuing the current window state.
            QWindowSystemInterface::handleWindowStateChanged(window(), window()->windowState());

            // It also needs to be told immediately that the geometry it requested
            // did not apply, otherwise it will continue on as if it did, instead
            // of waiting for a resize event.
            [m_view layoutIfNeeded];
        }

        return;
    }

    applyGeometry(rect);
}

void QIOSWindow::applyGeometry(const QRect &rect)
{
    // Geometry changes are asynchronous, but QWindow::geometry() is
    // expected to report back the 'requested geometry' until we get
    // a callback with the updated geometry from the window system.
    // The baseclass takes care of persisting this for us.
    QPlatformWindow::setGeometry(rect);

    if (window()->isTopLevel()) {
        // The QWindow is in QScreen coordinates, which maps to a possibly rotated root-view-controller.
        // Since the root-view-controller might be translated in relation to the UIWindow, we need to
        // check specifically for that and compensate. Also check if the root view has been scrolled
        // as a result of the keyboard being open.
        UIWindow *uiWindow = m_view.window;
        UIView *rootView = uiWindow.rootViewController.view;
        CGRect rootViewPositionInRelationToRootViewController =
            [rootView convertRect:uiWindow.bounds fromView:uiWindow];

        m_view.frame = CGRectOffset([m_view.superview convertRect:toCGRect(rect) fromView:rootView],
                rootViewPositionInRelationToRootViewController.origin.x,
                rootViewPositionInRelationToRootViewController.origin.y
                + rootView.bounds.origin.y);
    } else {
        // Easy, in parent's coordinates
        m_view.frame = toCGRect(rect);
    }

    // iOS will automatically trigger -[layoutSubviews:] for resize,
    // but not for move, so we force it just in case.
    [m_view setNeedsLayout];

    if (window()->inherits("QWidgetWindow"))
        [m_view layoutIfNeeded];
}

bool QIOSWindow::isExposed() const
{
    return qApp->applicationState() > Qt::ApplicationHidden
        && window()->isVisible() && !window()->geometry().isEmpty();
}

void QIOSWindow::setWindowState(Qt::WindowState state)
{
    // Update the QWindow representation straight away, so that
    // we can update the statusbar visibility based on the new
    // state before applying geometry changes.
    qt_window_private(window())->windowState = state;

    if (window()->isTopLevel() && window()->isVisible() && window()->isActive())
        static_cast<QIOSScreen *>(screen())->updateStatusBarVisibility();

    switch (state) {
    case Qt::WindowNoState:
        applyGeometry(m_normalGeometry);
        break;
    case Qt::WindowMaximized:
        applyGeometry(screen()->availableGeometry());
        break;
    case Qt::WindowFullScreen:
        applyGeometry(screen()->geometry());
        break;
    case Qt::WindowMinimized:
        applyGeometry(QRect());
        break;
    case Qt::WindowActive:
        Q_UNREACHABLE();
    default:
        Q_UNREACHABLE();
    }
}

void QIOSWindow::setParent(const QPlatformWindow *parentWindow)
{
    if (parentWindow) {
        UIView *parentView = reinterpret_cast<UIView *>(parentWindow->winId());
        [parentView addSubview:m_view];
    } else if (isQtApplication()) {
        for (UIWindow *uiWindow in [[UIApplication sharedApplication] windows]) {
            if (uiWindow.screen == static_cast<QIOSScreen *>(screen())->uiScreen()) {
                [uiWindow.rootViewController.view addSubview:m_view];
                break;
            }
        }
    }
}

void QIOSWindow::requestActivateWindow()
{
    // Note that several windows can be active at the same time if they exist in the same
    // hierarchy (transient children). But only one window can be QGuiApplication::focusWindow().
    // Dispite the name, 'requestActivateWindow' means raise and transfer focus to the window:
    if (blockedByModal())
        return;

    Q_ASSERT(m_view.window);
    [m_view.window makeKeyWindow];
    [m_view becomeFirstResponder];

    if (window()->isTopLevel())
        raise();
}

void QIOSWindow::raiseOrLower(bool raise)
{
    // Re-insert m_view at the correct index among its sibling views
    // (QWindows) according to their current m_windowLevel:
    if (!isQtApplication())
        return;

    NSArray *subviews = m_view.superview.subviews;
    if (subviews.count == 1)
        return;

    for (int i = int(subviews.count) - 1; i >= 0; --i) {
        UIView *view = static_cast<UIView *>([subviews objectAtIndex:i]);
        if (view.hidden || view == m_view || !view.qwindow)
            continue;
        int level = static_cast<QIOSWindow *>(view.qwindow->handle())->m_windowLevel;
        if (m_windowLevel > level || (raise && m_windowLevel == level)) {
            [m_view.superview insertSubview:m_view aboveSubview:view];
            return;
        }
    }
    [m_view.superview insertSubview:m_view atIndex:0];
}

void QIOSWindow::updateWindowLevel()
{
    Qt::WindowType type = windowType();

    if (type == Qt::ToolTip)
        m_windowLevel = 120;
    else if (window()->flags() & Qt::WindowStaysOnTopHint)
        m_windowLevel = 100;
    else if (window()->isModal())
        m_windowLevel = 40;
    else if (type == Qt::Popup)
        m_windowLevel = 30;
    else if (type == Qt::SplashScreen)
        m_windowLevel = 20;
    else if (type == Qt::Tool)
        m_windowLevel = 10;
    else
        m_windowLevel = 0;

    // A window should be in at least the same m_windowLevel as its parent:
    QWindow *transientParent = window()->transientParent();
    QIOSWindow *transientParentWindow = transientParent ? static_cast<QIOSWindow *>(transientParent->handle()) : 0;
    if (transientParentWindow)
        m_windowLevel = qMax(transientParentWindow->m_windowLevel, m_windowLevel);
}

void QIOSWindow::handleContentOrientationChange(Qt::ScreenOrientation orientation)
{
    // Keep the status bar in sync with content orientation. This will ensure
    // that the task bar (and associated gestures) are aligned correctly:
    UIInterfaceOrientation uiOrientation = UIInterfaceOrientation(fromQtScreenOrientation(orientation));
    [[UIApplication sharedApplication] setStatusBarOrientation:uiOrientation animated:NO];
}

void QIOSWindow::applicationStateChanged(Qt::ApplicationState)
{
    if (window()->isExposed() != isExposed())
        [m_view sendUpdatedExposeEvent];
}

qreal QIOSWindow::devicePixelRatio() const
{
    return m_view.contentScaleFactor;
}

void QIOSWindow::clearAccessibleCache()
{
    [m_view clearAccessibleCache];
}

#include "moc_qioswindow.cpp"

QT_END_NAMESPACE
