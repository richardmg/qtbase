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

// m_currentMenu points to the popup currently
// executing (only one popup should be open at a time)
QIOSMenu *QIOSMenu::m_currentMenu = 0;

// -------------------------------------------------------------------------

#define QIOS_MENUITEM_ACTION(index) \
    - (void)_qtMenuItem_ ## index \
    { \
        emit m_visibleMenuItems.at(index)->activated(); \
        QIOSMenu::currentMenu()->setVisible(false); \
    }

@interface QUIMenuControllerActionTarget : UIResponder {
    QIOSMenuItemList m_visibleMenuItems;
}
@end

@implementation QUIMenuControllerActionTarget

- (id)initWithVisibleMenuItems:(QIOSMenuItemList)visibleMenuItems
{
    if (self = [super init]) {
        m_visibleMenuItems = visibleMenuItems;
        NSMutableArray *menuItemArray = [NSMutableArray arrayWithCapacity:m_visibleMenuItems.size()];
        // Create an array of UIMenuItems, one for each visible QIOSMenuItem. Each
        // UIMenuItem needs a callback assigned, so we assign one of the placeholder methods
        // added to this class. Each method knows its own index, which corresponds
        // to the index of the corresponding QIOSMenuItem in m_visibleMenuItems.
        for (int i = 0; i < m_visibleMenuItems.count(); ++i) {
            QIOSMenuItem *item = m_visibleMenuItems.at(i);
            SEL sel = NSSelectorFromString([NSString stringWithFormat:@"_qtMenuItem_%i", i]);
            [menuItemArray addObject:[[[UIMenuItem alloc] initWithTitle:item->m_text.toNSString() action:sel] autorelease]];
        }
        [UIMenuController sharedMenuController].menuItems = menuItemArray;
    }

    return self;
}

- (id)targetForAction:(SEL)action withSender:(id)sender
{
    Q_UNUSED(sender);
    // iOS will determine which items in the the menu to show by calling (for each selector)
    // "- (id)targetForAction:(SEL)action withSender:(id)sender" up the responder chain. If no one
    // returns a target, the menu will not show. Implementations of this method is found inside
    // QUIWindow and QUIView, where both just forward the to this method.
    if ([self respondsToSelector:action])
        return self;

    return 0;
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

// -------------------------------------------------------------------------

@interface QUIActionSheet : UIActionSheet <UIActionSheetDelegate>{
    QIOSMenuItemList m_visibleMenuItems;
}
@end

@implementation QUIActionSheet

- (id)initWithVisibleMenuItems:(QIOSMenuItemList)visibleMenuItems title:(QString)title
{
    self = [super initWithTitle:title.isEmpty() ? nil : title.toNSString()
        delegate:self
        cancelButtonTitle:nil
        destructiveButtonTitle:nil
        otherButtonTitles:nil];

    if (self) {
        m_visibleMenuItems = visibleMenuItems;
        for (int i = 0; i < visibleMenuItems.count(); ++i)
            [self addButtonWithTitle:m_visibleMenuItems.at(i)->m_text.toNSString()];
    }

    return self;
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)index
{
    Q_UNUSED(actionSheet);
    emit m_visibleMenuItems.at(index)->activated();
    QIOSMenu::currentMenu()->setVisible(false);
}

@end

// -------------------------------------------------------------------------

@interface QUIPickerView : UIPickerView <UIPickerViewDelegate, UIPickerViewDataSource> {
    QIOSMenuItemList m_visibleMenuItems;
    NSInteger m_selectedRow;
}
@end

@implementation QUIPickerView

- (id)initWithVisibleMenuItems:(QIOSMenuItemList)visibleMenuItems selectItem:(const QIOSMenuItem *)selectItem
{
    if (self = [super init]) {
        m_visibleMenuItems = visibleMenuItems;
        m_selectedRow = visibleMenuItems.indexOf(const_cast<QIOSMenuItem *>(selectItem));
        if (m_selectedRow == -1)
            m_selectedRow = 0;

        [self setDelegate:self];
        [self setDataSource:self];
        [self selectRow:m_selectedRow inComponent:0 animated:false];
    }

    return self;
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    Q_UNUSED(pickerView);
    Q_UNUSED(component);
    return m_visibleMenuItems.at(row)->m_text.toNSString();
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView
{
    Q_UNUSED(pickerView);
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
    Q_UNUSED(pickerView);
    Q_UNUSED(component);
    return m_visibleMenuItems.length();
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    Q_UNUSED(pickerView);
    Q_UNUSED(component);
    m_selectedRow = row;
}

- (void)closeMenu
{
    if (!m_visibleMenuItems.isEmpty())
        emit m_visibleMenuItems.at(m_selectedRow)->activated();
    QIOSMenu::currentMenu()->setVisible(false);
}

@end

// -------------------------------------------------------------------------

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
    , m_effectiveVisible(false)
    , m_text(QString())
    , m_menuType(DefaultMenu)
    , m_effectiveMenuType(DefaultMenu)
    , m_targetRect(QRect(qGuiApp->primaryScreen()->availableGeometry().center(), QSize()))
    , m_targetItem(0)
    , m_menuActionTarget(0)
    , m_actionSheet(0)
    , m_pickerView(0)
{
    connect(qGuiApp->inputMethod(), &QInputMethod::animatingChanged, this, &QIOSMenu::rootViewGeometryChanged);
}

QIOSMenu::~QIOSMenu()
{
    dismiss();
}

void QIOSMenu::insertMenuItem(QPlatformMenuItem *menuItem, QPlatformMenuItem *before)
{
    if (!before) {
        m_menuItems.append(static_cast<QIOSMenuItem *>(menuItem));
    } else {
        int index = m_menuItems.indexOf(static_cast<QIOSMenuItem *>(before)) + 1;
        m_menuItems.insert(index, static_cast<QIOSMenuItem *>(menuItem));
    }
}

void QIOSMenu::removeMenuItem(QPlatformMenuItem *menuItem)
{
    m_menuItems.removeOne(static_cast<QIOSMenuItem *>(menuItem));
}

void QIOSMenu::setTag(quintptr tag)
{
    m_tag = tag;
}

quintptr QIOSMenu::tag() const
{
    return m_tag;
}

void QIOSMenu::setText(const QString &text)
{
   m_text = text;
}

void QIOSMenu::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;

    m_enabled = enabled;
    updateVisibility();
}

void QIOSMenu::showPopup(const QWindow *parentWindow, const QRect &targetRect, const QPlatformMenuItem *item)
{
    m_targetRect = QRect(parentWindow->mapToGlobal(targetRect.topLeft()), targetRect.size());
    m_targetItem = static_cast<const QIOSMenuItem *>(item);
    setVisible(true);
}

void QIOSMenu::dismiss()
{
    setVisible(false);
}

void QIOSMenu::setVisible(bool visible)
{
    if (m_visible == visible)
        return;

    m_visible = visible;
    updateVisibility();
}

void QIOSMenu::updateVisibility()
{
    bool visibleAndEnabled = m_visible && m_enabled;
    if ((visibleAndEnabled && m_effectiveVisible) || (!visibleAndEnabled && m_currentMenu != this))
        return;

    m_effectiveVisible = visibleAndEnabled;

    if (m_effectiveVisible) {
        Q_ASSERT(m_currentMenu != this);
        if (m_currentMenu)
            m_currentMenu->setVisible(false);
        m_currentMenu = this;
        m_effectiveMenuType = m_menuType;
        emit aboutToShow();
    }

    if (m_effectiveMenuType == EditMenu)
        updateVisibilityUsingUIMenuController();
    else
        updateVisibilityUsingUIPickerView();

    if (!m_effectiveVisible) {
        // Emit the signal after the fact in case
        // the app opens a popup when receiving it.
        if (m_currentMenu == this)
            m_currentMenu = 0;
        emit aboutToHide();
    }
}

void QIOSMenu::setMenuType(QPlatformMenu::MenuType type)
{
    m_menuType = type;
}

void QIOSMenu::updateVisibilityUsingUIMenuController()
{
    UIMenuController *menuController = [UIMenuController sharedMenuController];

    if (m_effectiveVisible) {
        Q_ASSERT(!m_menuActionTarget);
        m_menuActionTarget = [[QUIMenuControllerActionTarget alloc] initWithVisibleMenuItems:visibleMenuItems()];
        UIView *view = [UIApplication sharedApplication].keyWindow.rootViewController.view;
        [menuController setTargetRect:toCGRect(m_targetRect) inView:view];

        if (QWindow *w = qGuiApp->focusWindow()) {
            // The first responder will get the menu action callbacks, so we need to set it:
            [reinterpret_cast<UIView *>(w->winId()) becomeFirstResponder];
            [menuController setMenuVisible:YES animated:YES];
        }
    } else {
        Q_ASSERT(m_menuActionTarget);
        [menuController setMenuVisible:NO animated:YES];
        [m_menuActionTarget release];
        m_menuActionTarget = 0;
    }
}

void QIOSMenu::updateVisibilityUsingUIActionSheet()
{
    if (m_effectiveVisible) {
        Q_ASSERT(!m_actionSheet);
        m_actionSheet = [[QUIActionSheet alloc] initWithVisibleMenuItems:visibleMenuItems() title:m_text];
        UIView *view = [UIApplication sharedApplication].keyWindow.rootViewController.view;
        [m_actionSheet showFromRect:toCGRect(m_targetRect) inView:view animated:YES];
    } else {
        Q_ASSERT(m_actionSheet);
        [m_actionSheet release];
        m_actionSheet = 0;
    }
}

void QIOSMenu::updateVisibilityUsingUIPickerView()
{
    if (m_effectiveVisible) {
        Q_ASSERT(!m_pickerView);
        m_pickerView = [[QUIPickerView alloc] initWithVisibleMenuItems:visibleMenuItems() selectItem:m_targetItem];

        if (QWindow *window = qGuiApp->focusWindow()) {
            QUIView *view = reinterpret_cast<QUIView *>(window->winId());
            view.inputView = m_pickerView;

            UIToolbar *toolbar = [[[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)] autorelease];
            UIBarButtonItem *doneButton = [[[UIBarButtonItem alloc]
                initWithBarButtonSystemItem: UIBarButtonSystemItemDone
                target:m_pickerView action:@selector(closeMenu)] autorelease];
            [toolbar setItems:[NSArray arrayWithObject:doneButton]];
            view.inputAccessoryView = toolbar;
            [view reloadInputViews];
        }
    } else {
        Q_ASSERT(m_pickerView);
        if (QWindow *window = qGuiApp->focusWindow()) {
            QUIView *view = reinterpret_cast<QUIView *>(window->winId());
            if (view.inputView == m_pickerView) {
                view.inputView = 0;
                view.inputAccessoryView = 0;
            }
            [view reloadInputViews];
        }
        // Give the keyboard a chance to close before deleting the picker view:
        [m_pickerView performSelector:@selector(release) withObject:0 afterDelay:2.0];
        m_pickerView = 0;
    }
}

QIOSMenuItemList QIOSMenu::visibleMenuItems()
{
    QIOSMenuItemList visibleMenuItems;
    visibleMenuItems.reserve(m_menuItems.size());

    for (int i = 0; i < m_menuItems.count(); ++i) {
        QIOSMenuItem *item = m_menuItems.at(i);
        if (!item->m_enabled || !item->m_visible)
            continue;
        visibleMenuItems.append(item);
    }

    return visibleMenuItems;
}

void QIOSMenu::rootViewGeometryChanged()
{
    if (!m_effectiveVisible || qApp->inputMethod()->isAnimating())
        return;

    if (m_effectiveMenuType == EditMenu) {
        UIMenuController *menuController = [UIMenuController sharedMenuController];
        UIView *view = [UIApplication sharedApplication].keyWindow.rootViewController.view;
        [menuController setTargetRect:toCGRect(m_targetRect) inView:view];
        [menuController setMenuVisible:YES animated:YES];
    } else /* if (m_effectiveMenuType == OptionsMenu) */ {
        if (!qApp->inputMethod()->isVisible())
            m_currentMenu->setVisible(false);
    }
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
