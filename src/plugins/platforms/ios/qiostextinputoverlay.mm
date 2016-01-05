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
#include <QtGui/QStyleHints>

#include "qiosglobal.h"
#include "qiostextinputoverlay.h"
#include "qiosinputcontext.h"

@interface QIOSLoupe : UIView {
    UIView *_targetView;
    UIView *_snapshotView;
    UIView *_loupeImageView;
    UIView *_maskView;
}
@property (nonatomic, assign) CGPoint focalPoint;
@end

@implementation QIOSLoupe

- (id)initWithTargetView:(UIView *)targetView
{
    UIImage *loupeImage = [UIImage imageWithContentsOfFile:@"loupe1.png"];
    if (self = [self initWithFrame:CGRectMake(0, 0, loupeImage.size.width, loupeImage.size.height)]) {
        _targetView = [targetView retain];
        _snapshotView = nil;


        if (true) {
            _maskView = [[UIView alloc] initWithFrame:self.bounds];
            _maskView.layer.cornerRadius = _maskView.frame.size.width / 2;
            _maskView.layer.masksToBounds = YES;

            CALayer *layer = self.layer;
            layer.borderWidth = 0.75;
            layer.cornerRadius = self.frame.size.width / 2;
            layer.borderColor = [[UIColor lightGrayColor] CGColor];
            layer.shadowColor = [[UIColor grayColor] CGColor];
            layer.shadowOffset = CGSizeMake(0, 1);
            layer.shadowRadius = 2.0;
            layer.shadowOpacity = 0.75;
            [self addSubview:_maskView];
        } else {
            _maskView = [[UIView alloc] initWithFrame:CGRectOffset(CGRectInset(self.bounds, 3.0, 3.0), 0, -2.0)];
            _maskView.layer.cornerRadius = _maskView.frame.size.width / 2;
            _maskView.layer.masksToBounds = YES;
            [self addSubview:_maskView];
            _loupeImageView = [[UIImageView alloc] initWithImage:loupeImage];
            [self addSubview:_loupeImageView];
        }
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
    const CGFloat yOffset = 0 + (self.frame.size.height / 2);
    [super setCenter:CGPointMake(_focalPoint.x, _focalPoint.y - yOffset)];

    const CGFloat loupeScale = 1.5;
    CGFloat x = -(_focalPoint.x * loupeScale) + self.frame.size.width / 2;
    CGFloat y = -(_focalPoint.y * loupeScale) + self.frame.size.height / 2;
    CGFloat w = _targetView.frame.size.width * loupeScale;
    CGFloat h = _targetView.frame.size.height * loupeScale;

    UIView *newSnapshotView = [_targetView snapshotViewAfterScreenUpdates:NO];
    newSnapshotView.frame = CGRectMake(x, y, w, h);
    [_maskView addSubview:newSnapshotView];
    [_snapshotView removeFromSuperview];
    _snapshotView = newSnapshotView;
}

@end

// -------------------------------------------------------------------------

@interface QIOSLoupeRecognizer : UIGestureRecognizer <UIGestureRecognizerDelegate> {
    UIView *_targetView;
    QIOSLoupe *_loupeView;
    CGPoint _lastTouchPoint;
    QTimer _triggerLoupeTimer;
}
@end

@implementation QIOSLoupeRecognizer

- (id)init
{
    if (self = [super initWithTarget:self action:@selector(gestureStateChanged)]) {
        _targetView = nil;
        _loupeView = nil;
        self.enabled = YES;
        self.cancelsTouchesInView = YES;
        self.delaysTouchesEnded = NO;

        _triggerLoupeTimer.setInterval(QGuiApplication::styleHints()->startDragTime());
        _triggerLoupeTimer.setSingleShot(true);
        QObject::connect(&_triggerLoupeTimer, &QTimer::timeout, [=](){
            self.state = UIGestureRecognizerStateBegan;
        });
    }

    return self;
}

- (void)dealloc
{
    _triggerLoupeTimer.stop();
    [_targetView removeGestureRecognizer:self];
    [_targetView release];
    if (_loupeView)
        [self removeLoupeView];
    [super dealloc];
}

- (void)gestureStateChanged
{
    switch (self.state) {
    case UIGestureRecognizerStateBegan:
        [self createLoupeView];
        _loupeView.focalPoint = _lastTouchPoint;
        break;
    case UIGestureRecognizerStateChanged:
        _loupeView.focalPoint = _lastTouchPoint;
        break;
    default:
        [self removeLoupeView];
        break;
    }

        // Trenger her å finne text posisjon for touch pos!!!!!!
        // Kanskje faktorere ut dette i en egen delegate?

        //    QList<QInputMethodEvent::Attribute> attrs;
        //    attrs << QInputMethodEvent::Attribute(QInputMethodEvent::Selection, 10, 0, 0);
        //    QInputMethodEvent e(QString(), attrs);
        //    QCoreApplication::sendEvent(QGuiApplication::focusObject(), &e);

}
- (void)update:(const Qt::InputMethodQueries &)updatedProperties
{
    Q_UNUSED(updatedProperties)

    UIView *desktopView = [UIApplication sharedApplication].keyWindow.rootViewController.view;

    if (_targetView != desktopView) {
        [_targetView removeGestureRecognizer:self];
        [_targetView release];
        [desktopView addGestureRecognizer:self];
        _targetView = [desktopView retain];
    }
}

- (void)createLoupeView
{
    _loupeView = [[QIOSLoupe alloc] initWithTargetView:_targetView];
    [_targetView.superview addSubview:_loupeView];
}

- (void)removeLoupeView
{
    [_loupeView removeFromSuperview];
    [_loupeView release];
    _loupeView = nil;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    _lastTouchPoint = [static_cast<UITouch *>([touches anyObject]) locationInView:_targetView];

    if ([event allTouches].count > 1) {
        _triggerLoupeTimer.stop();
        self.state = UIGestureRecognizerStateFailed;
    } else {
        QTransform tf = QGuiApplication::inputMethod()->inputItemTransform();
        QRectF inputRect = tf.mapRect(QGuiApplication::inputMethod()->inputItemRectangle());
        if (inputRect.contains(fromCGPoint(_lastTouchPoint)))
            _triggerLoupeTimer.start();
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];
    if (self.state == UIGestureRecognizerStatePossible) {
        CGPoint p = [static_cast<UITouch *>([touches anyObject]) locationInView:_targetView];
        CGFloat dist = hypot(_lastTouchPoint.x - p.x, _lastTouchPoint.y - p.y);
        if (dist > QGuiApplication::styleHints()->startDragDistance()) {
            _triggerLoupeTimer.stop();
            self.state = UIGestureRecognizerStateFailed;
        }
    } else {
        _lastTouchPoint = [static_cast<UITouch *>([touches anyObject]) locationInView:_targetView];
        self.state = UIGestureRecognizerStateChanged;
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    _lastTouchPoint = [static_cast<UITouch *>([touches anyObject]) locationInView:_targetView];
    _triggerLoupeTimer.stop();
    self.state = UIGestureRecognizerStateEnded;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesCancelled:touches withEvent:event];
    _lastTouchPoint = [static_cast<UITouch *>([touches anyObject]) locationInView:_targetView];
    _triggerLoupeTimer.stop();
    self.state = UIGestureRecognizerStateCancelled;
}

@end

// -------------------------------------------------------------------------

QT_BEGIN_NAMESPACE

QIOSLoupeRecognizer *QIOSTextInputOverlay::s_loupeRecognizer = Q_NULLPTR;

void QIOSTextInputOverlay::update(const Qt::InputMethodQueries &updatedProperties)
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
