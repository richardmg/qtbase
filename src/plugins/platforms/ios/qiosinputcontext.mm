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

#include "qiosinputcontext.h"
#include <qpa/qwindowsysteminterface.h>
#include <QDebug>

@interface QIOSKeyboardListener : UIView <UIKeyInput> {
@public
    QIOSInputContext *m_context;
    BOOL m_keyboardVisible;
}
@end

@implementation QIOSKeyboardListener

- (id)initWithQIOSInputContext:(QIOSInputContext *)context
{
    self = [super init];
    if (self) {
        m_context = context;
        m_keyboardVisible = NO;
        // After the keyboard became undockable (iOS5), UIKeyboardWillShow/UIKeyboardWillHide
        // does no longer work for all cases. So we listen to keyboard frame changes instead:
        [[NSNotificationCenter defaultCenter]
            addObserver:self
            selector:@selector(keyboardDidChangeFrame:)
            name:@"UIKeyboardDidChangeFrameNotification" object:nil];
    }
    return self;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter]
        removeObserver:self
        name:@"UIKeyboardDidChangeFrameNotification" object:nil];
    [super dealloc];
}

- (void) keyboardDidChangeFrame:(NSNotification *)notification
{
    CGRect frame;
    [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] getValue:&frame];
    BOOL visible = CGRectIntersectsRect(frame, [UIScreen mainScreen].bounds);
    if (m_keyboardVisible != visible) {
        m_keyboardVisible = visible;
        m_context->emitInputPanelVisibleChanged();
    }
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)hasText
{
    return YES;
}

- (void)insertText:(NSString *)text
{
    QString string = QString::fromUtf8([text UTF8String]);
    int key = 0;
    if ([text isEqualToString:@"\n"])
        key = (int)Qt::Key_Return;

    // Send key event to window system interface
    QWindowSystemInterface::handleKeyEvent(
        0, QEvent::KeyPress, key, Qt::NoModifier, string, false, int(string.length()));
    QWindowSystemInterface::handleKeyEvent(
        0, QEvent::KeyRelease, key, Qt::NoModifier, string, false, int(string.length()));
}

- (void)deleteBackward
{
    // Send key event to window system interface
    QWindowSystemInterface::handleKeyEvent(
        0, QEvent::KeyPress, (int)Qt::Key_Backspace, Qt::NoModifier);
    QWindowSystemInterface::handleKeyEvent(
        0, QEvent::KeyRelease, (int)Qt::Key_Backspace, Qt::NoModifier);
}

@end

QIOSInputContext::QIOSInputContext()
    : QPlatformInputContext(),
    m_keyboardListener([[QIOSKeyboardListener alloc] initWithQIOSInputContext:this])
{
    // Note: Qt will forward keyevents to whichever QObject that needs it, regardless of which UIView
    // the input acutually came from. So in this respect, we're undermining iOS' responder chain.
    // Documentation specifies that one should (re)call becomeFirstResponder/resignFirstResponder to
    // show/hide the keyboard, and since a view needs to implement the UIKeyInput protocol to receive
    // keyevents, we create a dummy view we can use solely for this purpose. This way we can control/steal
    // keyboard/keyinput also in the case were Qt is embedded inside a native app.
    [[UIApplication sharedApplication].delegate.window.rootViewController.view addSubview:m_keyboardListener];
}

QIOSInputContext::~QIOSInputContext()
{
    [m_keyboardListener release];
}

void QIOSInputContext::showInputPanel()
{
    [m_keyboardListener becomeFirstResponder];
}

void QIOSInputContext::hideInputPanel()
{
    [m_keyboardListener resignFirstResponder];
}

bool QIOSInputContext::isInputPanelVisible() const
{
    return m_keyboardListener->m_keyboardVisible;
}
