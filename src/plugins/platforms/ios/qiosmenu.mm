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
#include "qiosinputcontext.h"
#include "qiosintegration.h"
#include "qiostextresponder.h"

// m_currentMenu points to the currently visible menu.
// Only one menu will be visible at a time, and if a second menu
// is shown on top of a first, the first one will be told to hide.
QIOSMenu *QIOSMenu::m_currentMenu = 0;

// -------------------------------------------------------------------------

static NSString *const kSelectorPrefix = @"_qtMenuItem_";

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
            SEL sel = NSSelectorFromString([NSString stringWithFormat:@"%@%i:", kSelectorPrefix, i]);
            [menuItemArray addObject:[[[UIMenuItem alloc] initWithTitle:item->m_text.toNSString() action:sel] autorelease]];
        }
        [UIMenuController sharedMenuController].menuItems = menuItemArray;
    }

    return self;
}

- (id)targetForAction:(SEL)action withSender:(id)sender
{
    BOOL containsPrefix = ([NSStringFromSelector(action) rangeOfString:kSelectorPrefix].location != NSNotFound);
    return (containsPrefix && [sender isKindOfClass:[UIMenuController class]]) ? self : 0;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
    Q_UNUSED(selector);
    // Just return a dummy signature that NSObject can create an NSInvocation from.
    // We end up only checking selector in forwardInvocation anyway.
    return [super methodSignatureForSelector:@selector(methodSignatureForSelector:)];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    // Since none of the menu item selector methods actually exist, this function
    // will end up being called as a final resort. We can then handle the action.
    NSString *selector = NSStringFromSelector(invocation.selector);
    NSRange range = NSMakeRange(kSelectorPrefix.length, selector.length - kSelectorPrefix.length - 1);
    NSInteger selectedIndex = [[selector substringWithRange:range] integerValue];

    emit m_visibleMenuItems.at(selectedIndex)->activated();
    QIOSMenu::currentMenu()->setVisible(false);
}

@end

// -------------------------------------------------------------------------

@interface QUIPickerView : UIPickerView <UIPickerViewDelegate, UIPickerViewDataSource> {
    QIOSMenuItemList m_visibleMenuItems;
    QPointer<QObject> m_focusObjectWithPickerView;
    NSInteger m_selectedRow;
}

@property(retain) UIToolbar *toolbar;

@end

@implementation QUIPickerView

- (id)initWithVisibleMenuItems:(const QIOSMenuItemList &)visibleMenuItems selectItem:(const QIOSMenuItem *)selectItem
{
    if (self = [super init]) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        m_visibleMenuItems = visibleMenuItems;
        m_selectedRow = visibleMenuItems.indexOf(const_cast<QIOSMenuItem *>(selectItem));
        if (m_selectedRow == -1)
            m_selectedRow = 0;

        self.toolbar = [[[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 100, 44)] autorelease];
        self.toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        UIBarButtonItem *doneButton = [[[UIBarButtonItem alloc]
                initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                target:self action:@selector(closeMenu)] autorelease];
        UIBarButtonItem *spaceButton = [[[UIBarButtonItem alloc]
                initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                target:self action:@selector(closeMenu)] autorelease];
        UIBarButtonItem *cancelButton = [[[UIBarButtonItem alloc]
                initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                target:self action:@selector(cancelMenu)] autorelease];
        [self.toolbar setItems:[NSArray arrayWithObjects:doneButton, spaceButton, cancelButton, nil]];

        [self setDelegate:self];
        [self setDataSource:self];
        [self selectRow:m_selectedRow inComponent:0 animated:false];
    }

    return self;
}

-(void)dealloc
{
    self.toolbar = 0;
    [super dealloc];
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

- (void)cancelMenu
{
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
    , m_separator(false)
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
    m_text = removeMnemonics(text);
}

void QIOSMenuItem::setVisible(bool isVisible)
{
    m_visible = isVisible;
}

void QIOSMenuItem::setIsSeparator(bool isSeparator)
{
   m_separator = isSeparator;
}

void QIOSMenuItem::setRole(QPlatformMenuItem::MenuRole role)
{
    m_role = role;
}

void QIOSMenuItem::setEnabled(bool enabled)
{
    m_enabled = enabled;
}

QString QIOSMenuItem::removeMnemonics(const QString &original)
{
    // Copied from qcocoahelpers
    QString returnText(original.size(), 0);
    int finalDest = 0;
    int currPos = 0;
    int l = original.length();
    while (l) {
        if (original.at(currPos) == QLatin1Char('&')
            && (l == 1 || original.at(currPos + 1) != QLatin1Char('&'))) {
            ++currPos;
            --l;
            if (l == 0)
                break;
        } else if (original.at(currPos) == QLatin1Char('(') && l >= 4 &&
                   original.at(currPos + 1) == QLatin1Char('&') &&
                   original.at(currPos + 2) != QLatin1Char('&') &&
                   original.at(currPos + 3) == QLatin1Char(')')) {
            /* remove mnemonics its format is "\s*(&X)" */
            int n = 0;
            while (finalDest > n && returnText.at(finalDest - n - 1).isSpace())
                ++n;
            finalDest -= n;
            currPos += 4;
            l -= 4;
            continue;
        }
        returnText[finalDest] = original.at(currPos);
        ++currPos;
        ++finalDest;
        --l;
    }
    returnText.truncate(finalDest);
    return returnText;
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
    , m_pickerView(0)
{
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
    if (!parentWindow->isActive())
        const_cast<QWindow *>(parentWindow)->requestActivate();
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

    if (visibleAndEnabled && !qApp->focusObject()) {
        // Since the menus depend on communicating with a focus object, a focus object is required to show
        // the menu. Note that QIOSMenu::showPopup() will activate the parent window (and set a focus object)
        // before this function is called, so this should normally be the case. Not having a focus object is only
        // expected in a hybrid environment where the first responder can be something else than a QUIView (then
        // no QWindow will be active). If the focus object changes while the menu is visible, the menu will hide.
        qWarning() << "QIOSMenu: cannot open menu without any active QWindows!";
        return;
    }

    m_effectiveVisible = visibleAndEnabled;

    if (m_effectiveVisible) {
        Q_ASSERT(m_currentMenu != this);
        if (m_currentMenu) {
            // The current implementation allow only one visible
            // menu at a time, so close the one currently showing.
            m_currentMenu->setVisible(false);
        }

        m_currentMenu = this;
        m_effectiveMenuType = m_menuType;
        connect(qGuiApp, &QGuiApplication::focusObjectChanged, this, &QIOSMenu::hide);
    } else {
        disconnect(qGuiApp, &QGuiApplication::focusObjectChanged, this, &QIOSMenu::hide);
        m_currentMenu = 0;
    }

    switch (m_effectiveMenuType) {
    case EditMenu:
        updateVisibilityUsingUIMenuController();
        break;
    default:
        updateVisibilityUsingUIPickerView();
        break;
    }

    // Emit the signal after the fact in case a
    // receiver opens a new menu when receiving it.
    emit (m_effectiveVisible ? aboutToShow() : aboutToHide());
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
        repositionMenu();
        connect(qGuiApp->inputMethod(), &QInputMethod::keyboardRectangleChanged, this, &QIOSMenu::repositionMenu);
    } else {
        disconnect(qGuiApp->inputMethod(), &QInputMethod::keyboardRectangleChanged, this, &QIOSMenu::repositionMenu);

        Q_ASSERT(m_menuController);
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:YES];
        [m_menuController release];
        m_menuController = 0;
    }
}

void QIOSMenu::updateVisibilityUsingUIPickerView()
{
    static QObject *focusObjectWithPickerView = 0;

    if (m_effectiveVisible) {
        Q_ASSERT(!m_pickerView);
        m_pickerView = [[QUIPickerView alloc] initWithVisibleMenuItems:visibleMenuItems() selectItem:m_targetItem];

        Q_ASSERT(!focusObjectWithPickerView);
        focusObjectWithPickerView = qApp->focusWindow()->focusObject();
        focusObjectWithPickerView->installEventFilter(this);
        qApp->inputMethod()->update(Qt::ImPlatformData);
    } else {
        Q_ASSERT(focusObjectWithPickerView);
        focusObjectWithPickerView->removeEventFilter(this);
        qApp->inputMethod()->update(Qt::ImPlatformData);
        focusObjectWithPickerView = 0;

        Q_ASSERT(m_pickerView);
        [m_pickerView release];
        m_pickerView = 0;
    }
}

bool QIOSMenu::eventFilter(QObject *obj, QEvent *event)
{
    if (event->type() == QEvent::InputMethodQuery) {
        QInputMethodQueryEvent *queryEvent = static_cast<QInputMethodQueryEvent *>(event);
        if (queryEvent->queries() & Qt::ImPlatformData) {
            // Let object fill inn default query results
            obj->event(queryEvent);

            QVariantMap imPlatformData = queryEvent->value(Qt::ImPlatformData).toMap();
            imPlatformData.insert(kImePlatformDataInputView, QVariant::fromValue(static_cast<void *>(m_pickerView)));
            imPlatformData.insert(kImePlatformDataInputAccessoryView, QVariant::fromValue(static_cast<void *>(m_pickerView.toolbar)));
            queryEvent->setValue(Qt::ImPlatformData, imPlatformData);

            return true;
        }
    }

    return QObject::eventFilter(obj, event);
}

QIOSMenuItemList QIOSMenu::visibleMenuItems() const
{
    QIOSMenuItemList visibleMenuItems = m_menuItems;

    for (int i = visibleMenuItems.count() - 1; i >= 0; --i) {
        QIOSMenuItem *item = visibleMenuItems.at(i);
        if (!item->m_enabled || !item->m_visible || item->m_separator)
            visibleMenuItems.removeAt(i);
    }

    return visibleMenuItems;
}

void QIOSMenu::repositionMenu()
{
    switch (m_effectiveMenuType) {
    case EditMenu: {
        UIView *view = [UIApplication sharedApplication].keyWindow.rootViewController.view;
        [[UIMenuController sharedMenuController] setTargetRect:toCGRect(m_targetRect) inView:view];
        [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
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
