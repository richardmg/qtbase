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

@interface QIOSLoupe : UIView {
    UIView *_targetView;
    UIView *_snapshotView;
}
@property (nonatomic, assign) CGPoint focalPoint;
@end

@implementation QIOSLoupe

- (id)initWithTargetView:(UIView *)targetView
{
    if (self = [self initWithFrame:CGRectMake(0, 0, 128, 128)]) {
        _targetView = [targetView retain];
        _snapshotView = nil;

        self.layer.borderColor = [[UIColor lightGrayColor] CGColor];
        self.layer.borderWidth = 1;
        self.layer.cornerRadius = self.frame.size.width / 2;
        self.layer.masksToBounds = YES;
    }

    return self;
}

- (void)dealloc
{
    [_targetView release];
    [super dealloc];
}

- (void)setFocalPoint:(CGPoint)point
{
    _focalPoint = point;
    const CGFloat yOffset = 10 + (self.frame.size.height / 2);
    [super setCenter:CGPointMake(_focalPoint.x, _focalPoint.y - yOffset)];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    Q_UNUSED(rect)

    if (!QGuiApplication::focusWindow())
        return;

    UIView *newSnapshotView = [_targetView snapshotViewAfterScreenUpdates:NO];

    const CGFloat loupeScale = 1.5;
    CGFloat x = -(_focalPoint.x * loupeScale) + self.frame.size.width / 2;
    CGFloat y = -(_focalPoint.y * loupeScale) + self.frame.size.height / 2;
    CGFloat w = newSnapshotView.frame.size.width * loupeScale;
    CGFloat h = newSnapshotView.frame.size.height * loupeScale;

    newSnapshotView.frame = CGRectMake(x, y, w, h);
    [self addSubview:newSnapshotView];
    [_snapshotView removeFromSuperview];
    _snapshotView = newSnapshotView;
}

@end

// -------------------------------------------------------------------------

@interface QIOSLoupeRecognizer : UIGestureRecognizer <UIGestureRecognizerDelegate> {
    UIView *_targetView;
    QIOSLoupe *_loupeView;
    CGRect _editRect;
}
@end

@implementation QIOSLoupeRecognizer

- (id)init
{
    if (self = [super initWithTarget:self action:@selector(gestureStateChanged:)]) {
        _targetView = nil;
        _loupeView = nil;
        self.enabled = YES;
        self.cancelsTouchesInView = NO;
        self.delaysTouchesEnded = NO;
    }

    return self;
}

- (void)dealloc
{
    [_targetView removeGestureRecognizer:self];
    if (_loupeView)
        [self removeLoupeView];
    [super dealloc];
}

- (void)createLoupeView
{
    Q_ASSERT(!_loupeView);
    _loupeView = [[QIOSLoupe alloc] initWithTargetView:_targetView];
    [[UIApplication sharedApplication].keyWindow addSubview:_loupeView];
}

- (void)removeLoupeView
{
    [_loupeView removeFromSuperview];
    [_loupeView release];
    _loupeView = nil;
}

- (void)update:(const Qt::InputMethodQueries &)updatedProperties
{
    UIView *focusView = reinterpret_cast<UIView *>(QGuiApplication::focusWindow()->winId());
    if (_targetView != focusView) {
        [_targetView removeGestureRecognizer:self];
        [focusView addGestureRecognizer:self];
        _targetView = focusView;
    }

    if (updatedProperties & Qt::ImEditRectangle)
        _editRect = toCGRect(QGuiApplication::inputMethod()->editRectangle());
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
    self.state = UIGestureRecognizerStateBegan;

    if ([event allTouches].count == 1) {
        [self createLoupeView];
        _loupeView.focalPoint = [static_cast<UITouch *>([touches anyObject]) locationInView:_targetView];
    } else {
        [self removeLoupeView];
    }

}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];

    _loupeView.focalPoint = [static_cast<UITouch *>([touches anyObject]) locationInView:_targetView];

        // Trenger her å finne text posisjon for touch pos!!!!!!
        // Kanskje faktorere ut dette i en egen delegate?

        //    QList<QInputMethodEvent::Attribute> attrs;
        //    attrs << QInputMethodEvent::Attribute(QInputMethodEvent::Selection, 10, 0, 0);
        //    QInputMethodEvent e(QString(), attrs);
        //    QCoreApplication::sendEvent(QGuiApplication::focusObject(), &e);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    self.state = UIGestureRecognizerStateFailed;
    [self removeLoupeView];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesCancelled:touches withEvent:event];
    self.state = UIGestureRecognizerStateFailed;
    [self removeLoupeView];
}

- (void)gestureTriggered:(id)sender
{
    Q_UNUSED(sender);
}

@end

// -------------------------------------------------------------------------

// -------------------------------------------------------------------------

QT_BEGIN_NAMESPACE

QIOSLoupeRecognizer *QIOSTextEditOverlay::s_loupeRecognizer = Q_NULLPTR;

void QIOSTextEditOverlay::update(const Qt::InputMethodQueries &updatedProperties)
{
    // need to ensure input context is updated before this call to use the following:
    // bool imEnabled = QIOSInputContext::instance()->inputMethodAccepted();

    QObject *focusObject = qGuiApp->focusObject();
    QInputMethodQueryEvent queryEvent(Qt::ImEnabled);
    QCoreApplication::sendEvent(focusObject, &queryEvent);
    bool imEnabled = queryEvent.value(Qt::ImEnabled).toBool();

    if (imEnabled && !s_loupeRecognizer)
        s_loupeRecognizer = [QIOSLoupeRecognizer new];
    [s_loupeRecognizer update:updatedProperties];
}

QT_END_NAMESPACE
