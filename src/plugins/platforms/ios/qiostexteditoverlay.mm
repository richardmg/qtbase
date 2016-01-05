/****************************************************************************
**
** Copyright (C) 2015 The Qt Company Ltd.
** Contact: http://www.qt.io/licensing/
**
** This file is part of the plugins of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:LGPL21$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see http://www.qt.io/terms-conditions. For further
** information use the contact form at http://www.qt.io/contact-us.
**
** GNU Lesser General Public License Usage
** Alternatively, this file may be used under the terms of the GNU Lesser
** General Public License version 2.1 or version 3 as published by the Free
** Software Foundation and appearing in the file LICENSE.LGPLv21 and
** LICENSE.LGPLv3 included in the packaging of this file. Please review the
** following information to ensure the GNU Lesser General Public License
** requirements will be met: https://www.gnu.org/licenses/lgpl.html and
** http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
**
** As a special exception, The Qt Company gives you certain additional
** rights. These rights are described in The Qt Company LGPL Exception
** version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
**
** $QT_END_LICENSE$
**
****************************************************************************/

#import <UIKit/UIGestureRecognizerSubclass.h>
#import <UIKit/UITextView.h>

#include <QtGui/QGuiApplication>
#include <QtGui/QWindow>

#include "qiosglobal.h"
#include "qiostexteditoverlay.h"
#include "qiosinputcontext.h"

@interface TransparentUITextView : UITextView {
@public
    BOOL _pretendToBeFirstResponder;
}
@end

@interface TextViewTouchListener : UIGestureRecognizer <UIGestureRecognizerDelegate> {
    TransparentUITextView *_targetView;
    BOOL _loupeShowing;
    UIEvent *_fakeTouchesCancelledEvent;
}
@end

// -------------------------------------------------------------------------

@implementation TextViewTouchListener

- (id)init
{
    if (self = [super initWithTarget:self action:@selector(gestureStateChanged:)]) {
        _loupeShowing = NO;
        _fakeTouchesCancelledEvent = nil;
        self.enabled = YES;
        self.cancelsTouchesInView = NO;
        self.delaysTouchesEnded = NO;
    }

    return self;
}

-(BOOL)setTargetView:(TransparentUITextView *)targetView
{
    _targetView = targetView;
    [_targetView addGestureRecognizer:self];

    // todo: reverse the check to avoid using string....
    // todo: can I achive this by using the canPrevent functions?
    // todo: should this function go into init?

    for (UIGestureRecognizer *gr in _targetView.gestureRecognizers) {
        if ([NSStringFromClass(gr.class) isEqualToString:@"UIVariableDelayLoupeGesture"]) {
            qDebug() << "Found loupe!";
            [gr addTarget:self action:@selector(loupeStateChanged:)];
            return YES;
        }
    }
    return NO;
}

- (void)dealloc
{
    [_fakeTouchesCancelledEvent release];
    [super dealloc];
}

- (void)loupeStateChanged:(id)sender
{
    switch (static_cast<UIGestureRecognizer *>(sender).state) {
    case UIGestureRecognizerStateBegan:
        // Convert the last touch event into a touch cancel event that we send
        // to QUIView.
        _loupeShowing = YES;
        if (_fakeTouchesCancelledEvent) {
            UIView *view = reinterpret_cast<UIView *>(QGuiApplication::focusWindow()->winId());
            [view touchesCancelled:[_fakeTouchesCancelledEvent allTouches] withEvent:_fakeTouchesCancelledEvent];
            [_fakeTouchesCancelledEvent release];
            _fakeTouchesCancelledEvent = nil;
        }
        break;
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
        // When the magnifier is done, we no longer need to
        // pretend that TransparentUITextView is first responder.
        _targetView->_pretendToBeFirstResponder = NO;
        break;
    default:
        break;
    }
}

- (void)gestureStateChanged:(id)sender
{
    Q_UNUSED(sender);
}

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other
{
    Q_UNUSED(other);
    return NO;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    // Forward all touch events to the QWindow that has focus (by sending them through the backing
    // QUIView). We need to do this using a gesture recognizer (as opposed to method overriding) since
    // other attached recognizers (e.g UITapGestureRecognizer) will send touch cancel to UITextView
    // to control local behavior. This
    // in turn would make touch forwarding to Qt break, if done that way.
    [super touchesBegan:touches withEvent:event];

    _loupeShowing = NO;
    self.state = UIGestureRecognizerStateBegan;
    [_fakeTouchesCancelledEvent release];
    _fakeTouchesCancelledEvent = [event retain];
    _targetView->_pretendToBeFirstResponder = YES;

    UIView *view = reinterpret_cast<UIView *>(QGuiApplication::focusWindow()->winId());
    [view touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];

    if (!_loupeShowing) {
        [_fakeTouchesCancelledEvent release];
        _fakeTouchesCancelledEvent = [event retain];
        UIView *view = reinterpret_cast<UIView *>(QGuiApplication::focusWindow()->winId());
        [view touchesMoved:touches withEvent:event];
    } else {
        // Trenger her å finne text posisjon for touch pos!!!!!!
        // Kanskje faktorere ut dette i en egen delegate?

        //    QList<QInputMethodEvent::Attribute> attrs;
        //    attrs << QInputMethodEvent::Attribute(QInputMethodEvent::Selection, 10, 0, 0);
        //    QInputMethodEvent e(QString(), attrs);
        //    QCoreApplication::sendEvent(QGuiApplication::focusObject(), &e);
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    if (_loupeShowing)
        return;

    self.state = UIGestureRecognizerStateFailed;
    _fakeTouchesCancelledEvent = [event retain];
    UIView *view = reinterpret_cast<UIView *>(QGuiApplication::focusWindow()->winId());
    [view touchesEnded:touches withEvent:event];
    _targetView->_pretendToBeFirstResponder = NO;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesCancelled:touches withEvent:event];
    if (_loupeShowing)
        return;

    self.state = UIGestureRecognizerStateFailed;
    UIView *view = reinterpret_cast<UIView *>(QGuiApplication::focusWindow()->winId());
    [view touchesCancelled:touches withEvent:event];
}

- (void)gestureTriggered:(id)sender
{
    Q_UNUSED(sender);
}

@end

// -------------------------------------------------------------------------

@implementation TransparentUITextView

-(id)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame textContainer:nil]) {
        _pretendToBeFirstResponder = NO;
        self.backgroundColor = [UIColor clearColor];
        self.tintColor = [UIColor clearColor];
        self.textColor = [UIColor clearColor];
    }
    return self;
}

- (BOOL)canBecomeFirstResponder
{
    // Text input should go to QIOSTextResponder, so we
    // refuse to become first responder.
    return NO;
}

- (BOOL)isFirstResponder
{
    // We need to lie and say that we're first responder
    // for the magnifier to show. This is a fragile part of
    // the implementation in case someone calls this method
    // for other purposes than showing the magnifier. To limit
    // that possibility, we return yes only while the user has a
    // touch press on the text view, or the magnifier is already
    // showing. We catch both cases from TextViewTouchListener.
    return _pretendToBeFirstResponder;
}

- (BOOL)becomeFirstResponder
{
    return NO;
}

- (BOOL)resignFirstResponder
{
    return YES;
}

@end

// -------------------------------------------------------------------------

QT_BEGIN_NAMESPACE

TransparentUITextView *QIOSTextEditOverlay::s_textView = Q_NULLPTR;
TextViewTouchListener *QIOSTextEditOverlay::s_gestureRecognizer = Q_NULLPTR;

void QIOSTextEditOverlay::createOverlay()
{
    if (s_textView)
        return;

    CGRect frame = toCGRect(QGuiApplication::inputMethod()->editRectangle());
    s_textView = [[TransparentUITextView alloc] initWithFrame:frame];
    s_gestureRecognizer = [TextViewTouchListener new];

    if (![s_gestureRecognizer setTargetView:s_textView]) {
        qWarning() << "Could not attach QIOSTextEditOverlay";
        deleteOverlay();
        return;
    }

    UIView *targetView = reinterpret_cast<UIView *>(QGuiApplication::focusWindow()->winId());
    [targetView addSubview:s_textView];
}

void QIOSTextEditOverlay::deleteOverlay()
{
    if (!s_textView)
        return;

    [s_textView removeGestureRecognizer:s_gestureRecognizer];
    [s_gestureRecognizer release];
    s_gestureRecognizer = nil;

    [s_textView removeFromSuperview];
    [s_textView release];
    s_textView = nil;
}

void QIOSTextEditOverlay::update(const Qt::InputMethodQueries &updatedProperties)
{
    // need to ensure input context is updated before this call to use the following:
    // bool imEnabled = QIOSInputContext::instance()->inputMethodAccepted();

    QObject *focusObject = qGuiApp->focusObject();
    QInputMethodQueryEvent queryEvent(Qt::ImEnabled);
    QCoreApplication::sendEvent(focusObject, &queryEvent);
    bool imEnabled = queryEvent.value(Qt::ImEnabled).toBool();

    if (imEnabled) {
        createOverlay();
        if (updatedProperties & Qt::ImEditRectangle)
            s_textView.frame = toCGRect(QGuiApplication::inputMethod()->editRectangle());
    } else {
        deleteOverlay();
    }
}

QT_END_NAMESPACE
