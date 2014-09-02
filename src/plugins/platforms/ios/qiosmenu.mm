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

@interface QUIMenuController : UIResponder {
    QIOSMenuItemList m_visibleMenuItems;
}
@end

@implementation QUIMenuController

- (id)initWithVisibleMenuItems:(const QIOSMenuItemList &)visibleMenuItems
{
    if (self = [super init]) {
        m_visibleMenuItems = visibleMenuItems;
        NSMutableArray *menuItemArray = [NSMutableArray arrayWithCapacity:m_visibleMenuItems.size()];
        // Create an array of UIMenuItems, one for each visible QIOSMenuItem. Each
        // UIMenuItem needs a callback assigned, so we assign one of the placeholder methods
        // added to UIWindow (QIOSMenuActionTargets) below. Each method knows its own index, which
        // corresponds to the index of the corresponding QIOSMenuItem in m_visibleMenuItems. When
        // triggered, menuItemActionCallback will end up being called.
        for (int i = 0; i < m_visibleMenuItems.count(); ++i) {
            QIOSMenuItem *item = m_visibleMenuItems.at(i);
            SEL sel = NSSelectorFromString([NSString stringWithFormat:@"_qtMenuItem_%i", i]);
            [menuItemArray addObject:[[[UIMenuItem alloc] initWithTitle:item->m_text.toNSString() action:sel] autorelease]];
        }
        [UIMenuController sharedMenuController].menuItems = menuItemArray;
    }

    return self;
}

-(void)showMenu:(BOOL)show targetRect:(const QRect &)targetRect
{
    if (show) {
        UIView *view = [UIApplication sharedApplication].keyWindow.rootViewController.view;
        [[UIMenuController sharedMenuController] setTargetRect:toCGRect(targetRect) inView:view];
    }
    [[UIMenuController sharedMenuController] setMenuVisible:show animated:YES];
}

-(void)menuitemActionCallback:(int)selectedIndex
{
    emit m_visibleMenuItems.at(selectedIndex)->activated();
    QIOSMenu::currentMenu()->setVisible(false);
}

@end

@interface UIView (QIOSMenuActionTargets)
@end

@implementation UIView (QIOSMenuActionTargets)
    // Since UIMenuItems need a callback selector to trigger when selected, we have
    // to predefine a number of callback methods that can be used. How many we need
    // depends on the number of items in the QMenu we display. We could generate them
    // dynamically to guarantee that we have a method for each QMenuItem, but to save
    // runtime and complexity we assume that the fixed number below should suffice.
#define QIOS_MENUITEM_ACTION(index) \
    - (void)_qtMenuItem_ ## index { QIOSMenu::currentMenu()->menuitemActionCallback(index); }

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

- (id)initWithVisibleMenuItems:(const QIOSMenuItemList &)visibleMenuItems title:(const QString &)title
{
    if (self = [super
            initWithTitle:title.isEmpty() ? nil : title.toNSString()
            delegate:self
            cancelButtonTitle:nil
            destructiveButtonTitle:nil
            otherButtonTitles:nil]) {
        m_visibleMenuItems = visibleMenuItems;
        for (int i = 0; i < visibleMenuItems.count(); ++i)
            [self addButtonWithTitle:m_visibleMenuItems.at(i)->m_text.toNSString()];
    }

    return self;
}

- (void)openSheetWithTargetRect:(const QRect &)rect
{
    UIView *view = [UIApplication sharedApplication].keyWindow.rootViewController.view;
    [self showFromRect:toCGRect(rect) inView:view animated:YES];
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
    QUIView *m_viewWithPickerAsInputView;
    NSInteger m_selectedRow;
}
@end

@implementation QUIPickerView

- (id)initWithVisibleMenuItems:(const QIOSMenuItemList &)visibleMenuItems selectItem:(const QIOSMenuItem *)selectItem
{
    if (self = [super init]) {
        m_visibleMenuItems = visibleMenuItems;
        m_viewWithPickerAsInputView = 0;
        m_selectedRow = visibleMenuItems.indexOf(const_cast<QIOSMenuItem *>(selectItem));
        if (m_selectedRow == -1)
            m_selectedRow = 0;

        [self setDelegate:self];
        [self setDataSource:self];
        [self selectRow:m_selectedRow inComponent:0 animated:false];
    }

    return self;
}

-(void)setAsInputView:(BOOL)set
{
    if (set) {
        Q_ASSERT(!m_viewWithPickerAsInputView);
        if (QWindow *window = qGuiApp->focusWindow()) {
            m_viewWithPickerAsInputView = [reinterpret_cast<QUIView *>(window->winId()) retain];
            m_viewWithPickerAsInputView.inputView = self;

            UIToolbar *toolbar = [[[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)] autorelease];
            UIBarButtonItem *doneButton = [[[UIBarButtonItem alloc]
                    initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                    target:self action:@selector(closeMenu)] autorelease];
            [toolbar setItems:[NSArray arrayWithObject:doneButton]];
            m_viewWithPickerAsInputView.inputAccessoryView = toolbar;
            [m_viewWithPickerAsInputView reloadInputViews];
        }
    } else {
        if (m_viewWithPickerAsInputView.inputView == self) {
            m_viewWithPickerAsInputView.inputView = 0;
            m_viewWithPickerAsInputView.inputAccessoryView = 0;
            [m_viewWithPickerAsInputView reloadInputViews];
        }
        [m_viewWithPickerAsInputView release];
        m_viewWithPickerAsInputView = 0;
    }
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
    , m_menuController(0)
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

    switch (m_effectiveMenuType) {
    case EditMenu:
        updateVisibilityUsingUIMenuController();
        break;
    case ActionMenu:
        updateVisibilityUsingUIActionSheet();
        break;
    default:
        updateVisibilityUsingUIPickerView();
        break;
    }

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
    if (m_effectiveVisible) {
        Q_ASSERT(!m_menuController);
        m_menuController = [[QUIMenuController alloc] initWithVisibleMenuItems:visibleMenuItems()];
        [m_menuController showMenu:true targetRect:m_targetRect];
    } else {
        Q_ASSERT(m_menuController);
        [m_menuController showMenu:false targetRect:m_targetRect];
        [m_menuController release];
        m_menuController = 0;
    }
}

void QIOSMenu::updateVisibilityUsingUIActionSheet()
{
    if (m_effectiveVisible) {
        Q_ASSERT(!m_actionSheet);
        m_actionSheet = [[QUIActionSheet alloc] initWithVisibleMenuItems:visibleMenuItems() title:m_text];
        [m_actionSheet openSheetWithTargetRect:m_targetRect];
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
        [m_pickerView setAsInputView:true];
    } else {
        Q_ASSERT(m_pickerView);
        [m_pickerView setAsInputView:false];
        [m_pickerView release];
        m_pickerView = 0;
    }
}

QIOSMenuItemList QIOSMenu::visibleMenuItems() const
{
    QIOSMenuItemList visibleMenuItems = m_menuItems;

    for (int i = visibleMenuItems.count() - 1; i >= 0; --i) {
        QIOSMenuItem *item = visibleMenuItems.at(i);
        if (!item->m_enabled || !item->m_visible)
            visibleMenuItems.removeAt(i);
    }

    return visibleMenuItems;
}

void QIOSMenu::rootViewGeometryChanged()
{
    if (!m_effectiveVisible || qApp->inputMethod()->isAnimating())
        return;

    switch (m_effectiveMenuType) {
    case EditMenu: {
        [m_menuController showMenu:true targetRect:m_targetRect];
        break; }
    default:
        break;
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

void QIOSMenu::menuitemActionCallback(int selectedIndex)
{
    [m_menuController menuitemActionCallback:selectedIndex];
}
