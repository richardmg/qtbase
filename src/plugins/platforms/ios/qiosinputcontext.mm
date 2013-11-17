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

#include "qiosglobal.h"
#include "qiosinputcontext.h"
#include "qioswindow.h"
#include <QGuiApplication>

@interface QIOSKeyboardListener : NSObject {
@public
    QIOSInputContext *m_context;
    BOOL m_keyboardVisible;
    BOOL m_keyboardVisibleAndDocked;
    QRectF m_keyboardRect;
    QRectF m_keyboardEndRect;
    NSTimeInterval m_duration;
    UIViewAnimationCurve m_curve;
    UIViewController *m_viewController;
}
@end

@implementation QIOSKeyboardListener

- (id)initWithQIOSInputContext:(QIOSInputContext *)context
{
    self = [super init];
    if (self) {
        m_context = context;
        m_keyboardVisible = NO;
        m_keyboardVisibleAndDocked = NO;
        m_duration = 0;
        m_curve = UIViewAnimationCurveEaseOut;
        m_viewController = 0;

        if (isQtApplication()) {
            // Get the root view controller that is on the same screen as the keyboard:
            for (UIWindow *uiWindow in [[UIApplication sharedApplication] windows]) {
                if (uiWindow.screen == [UIScreen mainScreen]) {
                    m_viewController = [uiWindow.rootViewController retain];
                    break;
                }
            }
            Q_ASSERT(m_viewController);
            Q_ASSERT([m_viewController.view isKindOfClass:[UIScrollView class]]);
        }

        [[NSNotificationCenter defaultCenter]
            addObserver:self
            selector:@selector(keyboardWillShow:)
            name:@"UIKeyboardWillShowNotification" object:nil];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
            selector:@selector(keyboardWillHide:)
            name:@"UIKeyboardWillHideNotification" object:nil];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
            selector:@selector(keyboardDidChangeFrame:)
            name:@"UIKeyboardDidChangeFrameNotification" object:nil];
    }
    return self;
}

- (void) dealloc
{
    [m_viewController release];
    [[NSNotificationCenter defaultCenter]
        removeObserver:self
        name:@"UIKeyboardWillShowNotification" object:nil];
    [[NSNotificationCenter defaultCenter]
        removeObserver:self
        name:@"UIKeyboardWillHideNotification" object:nil];
    [[NSNotificationCenter defaultCenter]
        removeObserver:self
        name:@"UIKeyboardDidChangeFrameNotification" object:nil];
    [super dealloc];
}

- (QRectF) getKeyboardRect:(NSNotification *)notification
{
    // For Qt applications we rotate the keyboard rect to align with the screen
    // orientation (which is the interface orientation of the root view controller).
    // For hybrid apps we follow native behavior, and return the rect unmodified:
    CGRect keyboardFrame = [[notification userInfo][UIKeyboardFrameEndUserInfoKey] CGRectValue];
    if (isQtApplication()) {
        UIView *scrollView = m_viewController.view;
        return fromCGRect(CGRectOffset([scrollView convertRect:keyboardFrame fromView:scrollView.window], 0, -scrollView.bounds.origin.y));
    } else {
        return fromCGRect(keyboardFrame);
    }
}

- (void) keyboardDidChangeFrame:(NSNotification *)notification
{
    m_keyboardRect = [self getKeyboardRect:notification];
    m_context->emitKeyboardRectChanged();

    BOOL visible = m_keyboardRect.intersects(fromCGRect([UIScreen mainScreen].bounds));
    if (m_keyboardVisible != visible) {
        m_keyboardVisible = visible;
        m_context->emitInputPanelVisibleChanged();
    }

    // If the keyboard was visible and docked from before, this is just a geometry
    // change (normally caused by an orientation change). In that case, update scroll:
    if (m_keyboardVisibleAndDocked)
        m_context->updateScrollView();
}

- (void) keyboardWillShow:(NSNotification *)notification
{
    // Note that UIKeyboardWillShowNotification is only sendt when the keyboard is docked.
    m_keyboardVisibleAndDocked = YES;
    m_keyboardEndRect = [self getKeyboardRect:notification];
    if (!m_duration) {
        m_duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        m_curve = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue] << 16;
    }
    m_context->updateScrollView();
}

- (void) keyboardWillHide:(NSNotification *)notification
{
    // Note that UIKeyboardWillHideNotification is also sendt when the keyboard is undocked.
    m_keyboardVisibleAndDocked = NO;
    m_keyboardEndRect = [self getKeyboardRect:notification];
    m_context->updateScrollView();
}

@end

QIOSInputContext::QIOSInputContext()
    : QPlatformInputContext()
    , m_keyboardListener([[QIOSKeyboardListener alloc] initWithQIOSInputContext:this])
    , m_focusView(0)
    , m_hasPendingHideRequest(false)
{
    if (m_keyboardListener->m_viewController)
        connect(qGuiApp->inputMethod(), &QInputMethod::cursorRectangleChanged, this, &QIOSInputContext::updateScrollView);
    connect(qGuiApp, &QGuiApplication::focusWindowChanged, this, &QIOSInputContext::focusWindowChanged);
}

QIOSInputContext::~QIOSInputContext()
{
    [m_keyboardListener release];
    [m_focusView release];
}

QRectF QIOSInputContext::keyboardRect() const
{
    return m_keyboardListener->m_keyboardRect;
}

void QIOSInputContext::showInputPanel()
{
    // Documentation tells that one should call (and recall, if necessary) becomeFirstResponder/resignFirstResponder
    // to show/hide the keyboard. This is slightly inconvenient, since there exist no API to get the current first
    // responder. Rather than searching for it from the top, we let the active QIOSWindow tell us which view to use.
    // Note that Qt will forward keyevents to whichever QObject that needs it, regardless of which UIView the input
    // actually came from. So in this respect, we're undermining iOS' responder chain.
    m_hasPendingHideRequest = false;

    // Ask the current focus object what kind of input it expects, and configure the keyboard appropriately:
    QObject *focusObject = QGuiApplication::focusObject();
    if (focusObject) {
        QInputMethodQueryEvent queryEvent(Qt::ImEnabled | Qt::ImHints);
        if (QCoreApplication::sendEvent(QGuiApplication::focusObject(), &queryEvent)) {
            if (queryEvent.value(Qt::ImEnabled).toBool()) {
                Qt::InputMethodHints hints = static_cast<Qt::InputMethodHints>(queryEvent.value(Qt::ImHints).toUInt());

                m_focusView.returnKeyType = (hints & Qt::ImhMultiLine) ? UIReturnKeyDefault : UIReturnKeyDone;
                m_focusView.secureTextEntry = BOOL(hints & Qt::ImhHiddenText);
                m_focusView.autocorrectionType = (hints & Qt::ImhNoPredictiveText) ?
                            UITextAutocorrectionTypeNo : UITextAutocorrectionTypeDefault;

                if (hints & Qt::ImhUppercaseOnly)
                    m_focusView.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
                else if (hints & Qt::ImhNoAutoUppercase)
                    m_focusView.autocapitalizationType = UITextAutocapitalizationTypeNone;
                else
                    m_focusView.autocapitalizationType = UITextAutocapitalizationTypeSentences;

                if (hints & Qt::ImhUrlCharactersOnly)
                    m_focusView.keyboardType = UIKeyboardTypeURL;
                else if (hints & Qt::ImhEmailCharactersOnly)
                    m_focusView.keyboardType = UIKeyboardTypeEmailAddress;
                else if (hints & Qt::ImhDigitsOnly)
                    m_focusView.keyboardType = UIKeyboardTypeNumberPad;
                else if (hints & Qt::ImhFormattedNumbersOnly)
                    m_focusView.keyboardType = UIKeyboardTypeDecimalPad;
                else if (hints & Qt::ImhDialableCharactersOnly)
                    m_focusView.keyboardType = UIKeyboardTypeNumberPad;
                else
                    m_focusView.keyboardType = UIKeyboardTypeNamePhonePad;
            }
        }
    }

    [m_focusView becomeFirstResponder];
}

void QIOSInputContext::hideInputPanel()
{
    // Delay hiding the keyboard for cases where the user is transferring focus between
    // 'line edits'. In that case the 'line edit' that lost focus will close the input
    // panel, just to see that the new 'line edit' will open it again:
    m_hasPendingHideRequest = true;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (m_hasPendingHideRequest)
            [m_focusView resignFirstResponder];
    });
}

bool QIOSInputContext::isInputPanelVisible() const
{
    return m_keyboardListener->m_keyboardVisible;
}

void QIOSInputContext::focusWindowChanged(QWindow *focusWindow)
{
    UIView<UIKeyInput> *view = reinterpret_cast<UIView<UIKeyInput> *>(focusWindow->handle()->winId());
    if ([m_focusView isFirstResponder])
        [view becomeFirstResponder];
    [m_focusView release];
    m_focusView = [view retain];
}

void QIOSInputContext::updateScrollView()
{
    // Scroll the screen if:
    // - our backend controls the root view controller on the main screen (no hybrid app)
    // - the focus object is on the same screen as the keyboard.
    // - the first responder is a QUIView, and not some other foreign UIView.
    // - the keyboard is docked. Otherwise the user can move the keyboard instead.
    if (!isQtApplication() || !m_focusView)
        return;

    UIView *scrollView = m_keyboardListener->m_viewController.view;
    qreal scrollTo = 0;

    if (m_focusView.isFirstResponder
            && m_keyboardListener->m_keyboardVisibleAndDocked
            && m_focusView.window == scrollView.window) {
        QRectF cursorRect = qGuiApp->inputMethod()->cursorRectangle();
        cursorRect.translate(qGuiApp->focusWindow()->geometry().topLeft());
        qreal keyboardY = m_keyboardListener->m_keyboardEndRect.y();
        int statusBarY = qGuiApp->primaryScreen()->availableGeometry().y();
        const int margin = 20;

        if (cursorRect.bottomLeft().y() > keyboardY - margin)
            scrollTo = qMin(scrollView.bounds.size.height - keyboardY, cursorRect.y() - statusBarY - margin);
    }

    if (scrollTo != scrollView.bounds.origin.y) {
        CGRect newBounds = scrollView.bounds;
        newBounds.origin.y = scrollTo;
        [UIView animateWithDuration:m_keyboardListener->m_duration delay:0
            options:m_keyboardListener->m_curve
            animations:^{ scrollView.bounds = newBounds; }
            completion: NULL];
    }
}
