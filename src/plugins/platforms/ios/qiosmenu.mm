/****************************************************************************
**
** Copyright (C) 2014 Digia Plc and/or its subsidiary(-ies).
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

#include <qglobal.h>
#include <qguiapplication.h>

#include "qiosglobal.h"
#include "qiosmenu.h"
#include "qioswindow.h"

#define QIOS_MENUITEM_ACTION(index) \
    - (void)_qtMenuItem_ ## index \
    { \
        if (g_currentMenu) \
            g_currentMenu->menuItemSelected(index); \
    }

// You can only have one menu open at a time
static QIOSMenu *g_currentMenu = 0;

@interface QIOSMenuActionTarget : UIResponder
@end

@implementation QIOSMenuActionTarget

- (id)targetForAction:(SEL)action withSender:(id)sender
{
    Q_UNUSED(sender);

    if ([self respondsToSelector:action])
        return self;

    return NULL;
}

// Since UIMenuItems need a callback selector to trigger when selected, we have
// to predefine a number of callback methods that can be used. How many we need
// depends on the number of items in the QMenu we display. We could generate them
// dynamically to guarantee that we have a method for each QMenuItem, but to save
// runtime and complexity we assume that the fixed number below should suffice.
QIOS_MENUITEM_ACTION(0)
QIOS_MENUITEM_ACTION(1)
QIOS_MENUITEM_ACTION(2)
QIOS_MENUITEM_ACTION(3)
QIOS_MENUITEM_ACTION(4)
QIOS_MENUITEM_ACTION(5)
QIOS_MENUITEM_ACTION(6)
QIOS_MENUITEM_ACTION(7)
QIOS_MENUITEM_ACTION(8)
QIOS_MENUITEM_ACTION(9)
QIOS_MENUITEM_ACTION(10)
QIOS_MENUITEM_ACTION(11)
QIOS_MENUITEM_ACTION(12)
QIOS_MENUITEM_ACTION(13)
QIOS_MENUITEM_ACTION(14)
QIOS_MENUITEM_ACTION(15)
QIOS_MENUITEM_ACTION(16)
QIOS_MENUITEM_ACTION(17)
QIOS_MENUITEM_ACTION(18)
QIOS_MENUITEM_ACTION(19)

@end

UIResponder *QIOSMenu::m_menuActionTarget = [[QIOSMenuActionTarget alloc] init];

QIOSMenuItem::QIOSMenuItem()
    : QPlatformMenuItem()
    , m_tag(0)
    , m_visible(true)
    , m_text(QString())
    , m_role(MenuRole(0))
    , m_enabled(true)
{
}

void QIOSMenuItem::setTag(quintptr tag)
{
    m_tag = tag;
}

quintptr QIOSMenuItem::tag() const
{
    return m_tag;
}

void QIOSMenuItem::setText(const QString &text)
{
    m_text = text;
}

void QIOSMenuItem::setVisible(bool isVisible)
{
    m_visible = isVisible;
}

void QIOSMenuItem::setRole(QPlatformMenuItem::MenuRole role)
{
    m_role = role;
}

void QIOSMenuItem::setEnabled(bool enabled)
{
    m_enabled = enabled;
}

QIOSMenu::QIOSMenu()
    : QPlatformMenu()
    , m_tag(0)
    , m_enabled(true)
    , m_visible(false)
    , m_targetRect(QRect(qGuiApp->primaryScreen()->availableGeometry().center(), QSize()))
{
    connect(qGuiApp->inputMethod(), &QInputMethod::animatingChanged, this, &QIOSMenu::rootViewGeometryChanged);
}

QIOSMenu::~QIOSMenu()
{
    dismiss();
}

void QIOSMenu::insertMenuItem(QPlatformMenuItem *menuItem, QPlatformMenuItem *before)
{
    if (!before)
        m_menuItems.append(menuItem);
    else
        m_menuItems.insert(m_menuItems.indexOf(before) + 1, menuItem);
}

void QIOSMenu::removeMenuItem(QPlatformMenuItem *menuItem)
{
    m_menuItems.removeOne(menuItem);
}

void QIOSMenu::setTag(quintptr tag)
{
    m_tag = tag;
}

quintptr QIOSMenu::tag() const
{
   return m_tag;
}

void QIOSMenu::setEnabled(bool enabled)
{
    m_enabled = enabled;
    setVisible(m_visible);
}

void QIOSMenu::showPopup(const QWindow *parentWindow, const QRect &targetRect, const QPlatformMenuItem *item)
{
    Q_UNUSED(item);
    m_targetRect = QRect(parentWindow->mapToGlobal(targetRect.topLeft()), targetRect.size());
    setVisible(true);
}

void QIOSMenu::dismiss()
{
    setVisible(false);
}

void QIOSMenu::setVisible(bool visible)
{
    m_visible = visible;
    UIMenuController *menuController = [UIMenuController sharedMenuController];

    if (m_enabled && m_visible) {
        // Create an array of UIMenuItems, one for each QIOSMenuItem in the QMenu. Each
        // UIMenuItem needs a callback assigned, so we assign one of the placeholder methods
        // added to QIOSMenuActionTarget. Each method knows its own index, which corresponds
        // to the index of the corresponding QIOSMenuItem in m_menuItems, and will call
        // QIOSMenu::menuItemSelected(int index) with it as argument upon trigger.
        NSMutableArray *menuItemArray = [NSMutableArray arrayWithCapacity:m_menuItems.size()];
        for (int i = 0; i < m_menuItems.count(); ++i) {
            QIOSMenuItem *item = static_cast<QIOSMenuItem *>(m_menuItems.at(i));
            if (!item->m_enabled || !item->m_visible)
                continue;
            SEL sel = NSSelectorFromString([NSString stringWithFormat:@"_qtMenuItem_%i", i]);
            [menuItemArray addObject:[[[UIMenuItem alloc] initWithTitle:item->m_text.toNSString() action:sel] autorelease]];
        }

        menuController.menuItems = menuItemArray;
        UIView *view = [UIApplication sharedApplication].keyWindow.rootViewController.view;
        [menuController setTargetRect:toCGRect(m_targetRect) inView:view];

        // iOS will determine which items in the the menu to show by calling (for each selector)
        // "- (id)targetForAction:(SEL)action withSender:(id)sender" up the responder chain. If no one
        // returns a target, the menu will not show. Implementations of this method is found inside
        // QUIWindow and QUIView, where both just forward the call to QIOSMenuActionTarget.
        if (g_currentMenu && g_currentMenu != this)
            g_currentMenu->setVisible(false);

        if (QWindow *w = qGuiApp->focusWindow()) {
            emit aboutToShow();
            [reinterpret_cast<UIView *>(w->winId()) becomeFirstResponder];
            [menuController setMenuVisible:YES animated:YES];
        }
        g_currentMenu = this;
    } else if (g_currentMenu == this) {
        // Only hide UIMenuController if this menu was the last one to show it
        emit aboutToHide();
        [menuController setMenuVisible:NO animated:YES];
        g_currentMenu = 0;
    }
}

void QIOSMenu::rootViewGeometryChanged()
{
    if (!m_enabled || !m_visible)
        return;

    UIMenuController *menuController = [UIMenuController sharedMenuController];
    UIView *view = [UIApplication sharedApplication].keyWindow.rootViewController.view;
    [menuController setTargetRect:toCGRect(m_targetRect) inView:view];
    [menuController setMenuVisible:YES animated:YES];
}

QPlatformMenuItem *QIOSMenu::menuItemAt(int position) const
{
    if (position < 0 || position >= m_menuItems.size())
        return 0;
    return m_menuItems.at(position);
}

QPlatformMenuItem *QIOSMenu::menuItemForTag(quintptr tag) const
{
    for (int i = 0; i < m_menuItems.size(); ++i) {
        QPlatformMenuItem *item = m_menuItems.at(i);
        if (item->tag() == tag)
            return item;
    }
    return 0;
}

void QIOSMenu::menuItemSelected(int index)
{
    emit m_menuItems.at(index)->activated();
    setVisible(false);
}
