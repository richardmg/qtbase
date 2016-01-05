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
#include <QtGui/QInputMethod>
#include <QtGui/QStyleHints>

#include <QtGui/private/qinputmethod_p.h>
#include <QtCore/private/qobject_p.h>

#include "qiosglobal.h"
#include "qiostextinputoverlay.h"

static QPlatformInputContext *platformInputContext()
{
    return static_cast<QInputMethodPrivate *>(QObjectPrivate::get(qApp->inputMethod()))->platformInputContext();
}

static bool hasSelection()
{
    QInputMethodQueryEvent query(Qt::ImAnchorPosition | Qt::ImCursorPosition);
    QGuiApplication::sendEvent(qGuiApp->focusObject(), &query);
    int anchorPos = query.value(Qt::ImAnchorPosition).toInt();
    int cursorPos = query.value(Qt::ImCursorPosition).toInt();
    return anchorPos != cursorPos;
}

// -------------------------------------------------------------------------

@interface QIOSEditMenu : NSObject
@property (nonatomic, assign) BOOL visible;
@property (nonatomic, readonly) BOOL willHide;
@property (nonatomic, assign) BOOL reshowAfterDidHide;
@end

@implementation QIOSEditMenu

- (id)init
{
    if (self = [super init]) {
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

        [center addObserverForName:UIMenuControllerWillHideMenuNotification
            object:nil queue:nil usingBlock:^(NSNotification *) {
            _willHide = YES;
        }];

        [center addObserverForName:UIMenuControllerDidHideMenuNotification
            object:nil queue:nil usingBlock:^(NSNotification *) {
            _willHide = NO;
            if (self.reshowAfterDidHide) {
                // To not abort an ongoing hide transition to reshow the menu, you can set
                // reshowAfterDidHide to wait until the transition finishes before reshowing
                // it. This looks better, and is also more close to native behavior.
                self.reshowAfterDidHide = NO;
                dispatch_async(dispatch_get_main_queue (), ^{ self.visible = YES; });
            }
        }];
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:nil];
    [super dealloc];
}

- (BOOL)visible
{
    return [UIMenuController sharedMenuController].menuVisible;
}

- (void)setVisible:(BOOL)visible
{
    if (visible == self.visible)
        return;

    if (visible) {
        // Note that the contents of the edit menu is decided by
        // first responder, which is normally QIOSTextResponder.
        QRectF cr = qApp->inputMethod()->cursorRectangle();
        QRectF ar = qApp->inputMethod()->anchorRectangle();
        CGRect targetRect = toCGRect(cr.united(ar));
        UIView *focusView = reinterpret_cast<UIView *>(qApp->focusWindow()->winId());
        [[UIMenuController sharedMenuController] setTargetRect:targetRect inView:focusView];
        [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
    } else {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:YES];
    }
}

@end

// -------------------------------------------------------------------------

@interface QIOSLoupeLayer : CALayer {
    UIView *_snapshotView;
    UIView *_loupeImageView;
    CALayer *_containerLayer;
    CGFloat _bottomOffset;
}
@property (nonatomic, retain) UIView *targetView;
@property (nonatomic, assign) CGPoint focalPoint;
@end

@implementation QIOSLoupeLayer

- (id)initWithFrame:(CGRect)frame cornerRadius:(CGFloat)cornerRadius bottomOffset:(CGFloat)bottomOffset
{
    if (self = [super init]) {
        self.frame = frame;
        _bottomOffset = bottomOffset;
        _snapshotView = nil;

        // Create outer loupe shadow
        self.cornerRadius = cornerRadius;
        self.shadowColor = [[UIColor grayColor] CGColor];
        self.shadowOffset = CGSizeMake(0, 1);
        self.shadowRadius = 2.0;
        self.shadowOpacity = 0.75;

        // Create container view for the snapshots
        _containerLayer = [[CALayer new] autorelease];
        _containerLayer.frame = self.frame;
        _containerLayer.cornerRadius = cornerRadius;
        _containerLayer.masksToBounds = YES;
        [self addSublayer:_containerLayer];

        // Create inner loupe shadow
        const CGFloat inset = 30;
        CALayer *topShadeLayer = [[CALayer new] autorelease];
        topShadeLayer.frame = CGRectOffset(CGRectInset(self.bounds, -inset, -inset), 0, inset / 2);
        topShadeLayer.borderWidth = inset / 2;
        topShadeLayer.cornerRadius = cornerRadius;
        topShadeLayer.borderColor = [[UIColor blackColor] CGColor];
        topShadeLayer.shadowColor = [[UIColor blackColor] CGColor];
        topShadeLayer.shadowOffset = CGSizeMake(0, 0);
        topShadeLayer.shadowRadius = 15.0;
        topShadeLayer.shadowOpacity = 0.6;
        // Keep the shadow inside the loupe
        CALayer *mask = [[CALayer new] autorelease];
        mask.frame = CGRectOffset(self.bounds, inset, inset / 2);
        mask.backgroundColor = [[UIColor blackColor] CGColor];
        mask.cornerRadius = cornerRadius;
        topShadeLayer.mask = mask;
        [self addSublayer:topShadeLayer];

        // Create border around the loupe. We need to do this in a separate
        // layer (as opposed to on self) to not draw the border on top of
        // overlapping external children (arrow).
        CALayer *borderLayer = [[CALayer new] autorelease];
        borderLayer.frame = self.frame;
        borderLayer.borderWidth = 0.75;
        borderLayer.cornerRadius = cornerRadius;
        borderLayer.borderColor = [[UIColor lightGrayColor] CGColor];
        [self addSublayer:borderLayer];
    }

    return self;
}

- (void)dealloc
{
    self.targetView = nil;
    [super dealloc];
}

- (void)setFocalPoint:(CGPoint)point
{
    // Take a snapshow of the target view, magnify the area around the focal
    // point, and add the snapshow layer as a child of the container layer
    // to make it look like a loupe. Then place this layer at the position of
    // the focal point with the requested offset.
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];

    _focalPoint = point;
    const CGFloat yOffset = _bottomOffset + (self.frame.size.height / 2);
    self.position = CGPointMake(_focalPoint.x, _focalPoint.y - yOffset);

    const CGFloat loupeScale = 1.5;
    CGFloat x = -(_focalPoint.x * loupeScale) + self.frame.size.width / 2;
    CGFloat y = -(_focalPoint.y * loupeScale) + self.frame.size.height / 2;
    CGFloat w = _targetView.frame.size.width * loupeScale;
    CGFloat h = _targetView.frame.size.height * loupeScale;

    UIView *newSnapshotView = [[_targetView snapshotViewAfterScreenUpdates:NO] retain];
    newSnapshotView.layer.frame = CGRectMake(x, y, w, h);
    [_containerLayer addSublayer:newSnapshotView.layer];
    [_snapshotView.layer removeFromSuperlayer];
    [_snapshotView release];
    _snapshotView = newSnapshotView;

    [CATransaction commit];
    [CATransaction flush];
}

@end

// -------------------------------------------------------------------------

@interface QIOSHandleLayer : CALayer {
    CALayer *_handleKnobLayer;
}
@property (nonatomic, assign) CGRect cursorRectangle;
@property (nonatomic, assign) BOOL visible;
@end

@implementation QIOSHandleLayer

- (id)init
{
    if (self = [super init]) {
        self.backgroundColor = [[UIColor blueColor] CGColor];

        _handleKnobLayer = [[CALayer new] autorelease];
        _handleKnobLayer.masksToBounds = YES;
        _handleKnobLayer.backgroundColor = self.backgroundColor;
        [self addSublayer:_handleKnobLayer];
    }
    return self;
}

- (void)setVisible:(BOOL)visible
{
    if (visible == _visible)
        return;

    _visible = visible;
    CGFloat midX = CGRectGetMidX(_cursorRectangle);
    CGFloat midY = CGRectGetMidY(_cursorRectangle);
    CGRect hiddenRect = CGRectMake(midX, midY, 0, 0);

    if (_visible) {
        [self moveHandleWithoutAnimation:hiddenRect];
        [self moveHandle:_cursorRectangle];
    } else {
        [self moveHandle:hiddenRect];
    }
}

- (void)setCursorRectangle:(CGRect)cursorRect
{
    if (CGRectEqualToRect(_cursorRectangle, cursorRect))
        return;

    _cursorRectangle = cursorRect;

    if (_visible)
        [self moveHandleWithoutAnimation:_cursorRectangle];
}

- (void)moveHandleWithoutAnimation:(CGRect)cursorRect
{
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    [self moveHandle:cursorRect];
    [CATransaction commit];
    [CATransaction flush];
}

- (void)moveHandle:(CGRect)targetRect
{
    // Posision the cursor bar:
    CGFloat barWidth = 2;
    CGRect barRect = targetRect;
    barRect.size.width = barWidth;
    barRect.origin.x += (targetRect.size.width - barWidth) / 2;
    self.frame = barRect;

    // Position the cursor knob:
    CGFloat knobWidth = targetRect.size.height == 0 ? 0 : 10;
    CGFloat knobX = (barWidth - knobWidth) / 2;
    CGFloat knobY = _cursorRectangle.size.height;
    _handleKnobLayer.frame = CGRectMake(knobX, knobY, knobWidth, knobWidth);
    _handleKnobLayer.cornerRadius = knobWidth / 2;
}

@end

// -------------------------------------------------------------------------

/**
  QIOSLoupeRecognizer is only a base class from which other recognisers
  below will inherit. It takes care of creating and showing a magnifier
  glass depending on the current gesture state.
  */
@interface QIOSLoupeRecognizer : UIGestureRecognizer <UIGestureRecognizerDelegate> {
    QIOSLoupeLayer *_loupeLayer;
    UIView *_desktopView;
    UIView *_focusView;
    CGPoint _firstTouchPoint;
    CGPoint _lastTouchPoint;
    QTimer _triggerStateBeganTimer;
}
@property (nonatomic, assign) QPointF focalPoint;
@property (nonatomic, assign) BOOL dragTriggersGesture;
@end

@implementation QIOSLoupeRecognizer

- (id)init
{
    if (self = [super initWithTarget:self action:@selector(gestureStateChanged)]) {
        self.enabled = NO;
        _triggerStateBeganTimer.setInterval(QGuiApplication::styleHints()->startDragTime());
        _triggerStateBeganTimer.setSingleShot(true);
        QObject::connect(&_triggerStateBeganTimer, &QTimer::timeout, [=](){
            self.state = UIGestureRecognizerStateBegan;
        });
    }

    return self;
}

- (void)setEnabled:(BOOL)enabled
{
    if (enabled == self.enabled)
        return;

    [super setEnabled:enabled];

    if (enabled) {
        _focusView = [reinterpret_cast<UIView *>(qApp->focusWindow()->winId()) retain];
        _desktopView = [[UIApplication sharedApplication].keyWindow.rootViewController.view retain];
        Q_ASSERT(_focusView && _desktopView && _desktopView.superview);
        [_desktopView addGestureRecognizer:self];
    } else {
        [_desktopView removeGestureRecognizer:self];
        [_desktopView release];
        _desktopView = nil;
        [_focusView release];
        _focusView = nil;
        _triggerStateBeganTimer.stop();
        if (_loupeLayer)
            [self removeLoupeLayer];
    }
}

- (void)gestureStateChanged
{
    switch (self.state) {
    case UIGestureRecognizerStateBegan:
        [self addLoupeLayer];
        [self updateFocalPoint:fromCGPoint(_lastTouchPoint)];
        break;
    case UIGestureRecognizerStateChanged:
        [self updateFocalPoint:fromCGPoint(_lastTouchPoint)];
        break;
    case UIGestureRecognizerStateEnded:
        QIOSTextInputOverlay::s_editMenu.visible = YES;
        [self removeLoupeLayer];
        break;
    default:
        [self removeLoupeLayer];
        break;
    }
}

- (void)addLoupeLayer
{
    // We magnify the the desktop view. But the loupe itself will be added as a child
    // of the desktop view's parent, so it doesn't become a part of what we magnify.
    _loupeLayer = [[self createLoupeLayer] retain];
    _loupeLayer.targetView = _desktopView;
    [_desktopView.superview.layer addSublayer:_loupeLayer];
}

- (void)removeLoupeLayer
{
    [_loupeLayer removeFromSuperlayer];
    [_loupeLayer release];
    _loupeLayer = nil;
}

- (QPointF)focalPoint
{
    return fromCGPoint([_loupeLayer.targetView convertPoint:_loupeLayer.focalPoint toView:_focusView]);
}

- (void)setFocalPoint:(QPointF)point
{
    _loupeLayer.focalPoint = [_loupeLayer.targetView convertPoint:toCGPoint(point) fromView:_focusView];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    if ([event allTouches].count > 1) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }

    _firstTouchPoint = [static_cast<UITouch *>([touches anyObject]) locationInView:_focusView];
    _lastTouchPoint = _firstTouchPoint;

    // If the touch point is accepted by the sub class (e.g touch on cursor), we start a
    // press'n'hold timer that eventually will move the state to UIGestureRecognizerStateBegan.
    if ([self acceptTouchesBegan:fromCGPoint(_firstTouchPoint)])
        _triggerStateBeganTimer.start();
    else
        self.state = UIGestureRecognizerStateFailed;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesMoved:touches withEvent:event];
    _lastTouchPoint = [static_cast<UITouch *>([touches anyObject]) locationInView:_focusView];

    if (self.state == UIGestureRecognizerStatePossible) {
        // If the touch was moved too far before the timer triggered (meaning that this
        // is a drag, not a press'n'hold), we should either fail, or trigger the gesture
        // immediatly, depending on self.dragTriggersGesture.
        int startDragDistance = QGuiApplication::styleHints()->startDragDistance();
        int dragDistance = hypot(_firstTouchPoint.x - _lastTouchPoint.x, _firstTouchPoint.y - _lastTouchPoint.y);
        if (dragDistance > startDragDistance) {
            _triggerStateBeganTimer.stop();
            self.state = self.dragTriggersGesture ? UIGestureRecognizerStateBegan : UIGestureRecognizerStateFailed;
        }
    } else {
        self.state = UIGestureRecognizerStateChanged;
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesEnded:touches withEvent:event];
    _triggerStateBeganTimer.stop();
    _lastTouchPoint = [static_cast<UITouch *>([touches anyObject]) locationInView:_focusView];
    self.state = self.state == UIGestureRecognizerStatePossible ? UIGestureRecognizerStateFailed : UIGestureRecognizerStateEnded;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesCancelled:touches withEvent:event];
    _triggerStateBeganTimer.stop();
    _lastTouchPoint = [static_cast<UITouch *>([touches anyObject]) locationInView:_focusView];
    self.state = UIGestureRecognizerStateCancelled;
}

// Methods implemented by subclasses:

- (BOOL)acceptTouchesBegan:(QPointF)touchPoint
{
    Q_UNUSED(touchPoint)
    Q_UNREACHABLE();
    return NO;
}

- (QIOSLoupeLayer *)createLoupeLayer
{
    Q_UNREACHABLE();
    return Q_NULLPTR;
}

- (void)updateFocalPoint:(QPointF)touchPoint
{
    Q_UNUSED(touchPoint)
    Q_UNREACHABLE();
}

@end

// -------------------------------------------------------------------------

/**
  This recognizer will be active when there's no selection. It will trigger if
  the user does a press and hold, which will start a session where the user can move
  the cursor around with his finger together with a magnifier glass.
  */
@interface QIOSCursorRecognizer : QIOSLoupeRecognizer
@end

@implementation QIOSCursorRecognizer

- (QIOSLoupeLayer *)createLoupeLayer
{
    return [[[QIOSLoupeLayer alloc] initWithFrame:CGRectMake(0, 0, 120, 120) cornerRadius:60 bottomOffset:4] autorelease];
}

- (BOOL)acceptTouchesBegan:(QPointF)touchPoint
{
    if (hasSelection())
        return NO;

    QTransform tf = QGuiApplication::inputMethod()->inputItemTransform();
    QRectF inputRect = tf.mapRect(QGuiApplication::inputMethod()->inputItemRectangle());
    return inputRect.contains(touchPoint);
}

- (void)updateFocalPoint:(QPointF)touchPoint
{
    self.focalPoint = touchPoint;
    platformInputContext()->setSelectionOnFocusObject(touchPoint, touchPoint);
}

@end

// -------------------------------------------------------------------------

/**
  This recognizer will watch for selections, and draw handles as overlay
  on the sides. If the user starts dragging on a handle (or do a press and
  hold), it will show a magnifier glass that follows the handle as it moves.
  */
@interface QIOSSelectionRecognizer : QIOSLoupeRecognizer {
    QIOSHandleLayer *_cursorLayer;
    QIOSHandleLayer *_anchorLayer;
    QPointF _touchOffset;
    bool _dragOnCursor;
}
@end

@implementation QIOSSelectionRecognizer

- (id)init
{
    if (self = [super init]) {
        self.delaysTouchesBegan = YES;
        self.dragTriggersGesture = YES;
        _cursorLayer = [QIOSHandleLayer new];
        _anchorLayer = [QIOSHandleLayer new];
        bool selection = hasSelection();
        _cursorLayer.visible = selection;
        _anchorLayer.visible = selection;
        UIView *focusView = reinterpret_cast<UIView *>(qApp->focusWindow()->winId());
        [focusView.layer addSublayer:_cursorLayer];
        [focusView.layer addSublayer:_anchorLayer];
    }

    return self;
}

- (void)dealloc
{
    [_cursorLayer removeFromSuperlayer];
    [_anchorLayer removeFromSuperlayer];
    [_cursorLayer release];
    [_anchorLayer release];
    [super dealloc];
}

- (QIOSLoupeLayer *)createLoupeLayer
{
    CGRect loupeFrame = CGRectMake(0, 0, 123, 33);
    CGSize arrowSize = CGSizeMake(25, 12);
    CGFloat loupeOffset = arrowSize.height + 20;

    // Build a triangular path to both draw and mask arrowLayer as a triangle
    UIBezierPath *path = [[UIBezierPath new] autorelease];
    [path moveToPoint:CGPointMake(0, 0)];
    [path addLineToPoint:CGPointMake(arrowSize.width / 2, arrowSize.height)];
    [path addLineToPoint:CGPointMake(arrowSize.width, 0)];

    QIOSLoupeLayer *loupeLayer = [[[QIOSLoupeLayer alloc] initWithFrame:loupeFrame cornerRadius:5 bottomOffset:loupeOffset] autorelease];
    CAShapeLayer *arrowLayer = [[[CAShapeLayer alloc] init] autorelease];
    arrowLayer.frame = CGRectMake((loupeFrame.size.width - arrowSize.width) / 2, loupeFrame.size.height - 1, arrowSize.width, arrowSize.height);
    arrowLayer.path = path.CGPath;
    arrowLayer.backgroundColor = [[UIColor whiteColor] CGColor];
    arrowLayer.strokeColor = [[UIColor lightGrayColor] CGColor];
    arrowLayer.lineWidth = 0.75 * 2;
    arrowLayer.fillColor = nil;

    CAShapeLayer *mask = [[CAShapeLayer new] autorelease];
    mask.frame = arrowLayer.bounds;
    mask.path = path.CGPath;
    arrowLayer.mask = mask;

    [loupeLayer addSublayer:arrowLayer];

    return loupeLayer;
}

- (BOOL)acceptTouchesBegan:(QPointF)touchPoint
{
    if (!hasSelection())
        return NO;

    const int handleRadius = 50;
    QPointF cursorCenter = qApp->inputMethod()->cursorRectangle().center();
    QPointF anchorCenter = qApp->inputMethod()->anchorRectangle().center();
    QPointF cursorOffset = QPointF(cursorCenter.x() - touchPoint.x(), cursorCenter.y() - touchPoint.y());
    QPointF anchorOffset = QPointF(anchorCenter.x() - touchPoint.x(), anchorCenter.y() - touchPoint.y());
    double cursorDist = hypot(cursorOffset.x(), cursorOffset.y());
    double anchorDist = hypot(anchorOffset.x(), anchorOffset.y());

    if (cursorDist > handleRadius && anchorDist > handleRadius)
        return NO;

    if (cursorDist < anchorDist) {
        _touchOffset = cursorOffset;
        _dragOnCursor = YES;
    } else {
        _touchOffset = anchorOffset;
        _dragOnCursor = NO;
    }

    return YES;
}

- (void)updateFocalPoint:(QPointF)touchPoint
{
    touchPoint += _touchOffset;

    if (_dragOnCursor) {
        QPointF anchorCenter = qApp->inputMethod()->anchorRectangle().center();
        platformInputContext()->setSelectionOnFocusObject(anchorCenter, touchPoint);
        QPointF cursorCenter = qApp->inputMethod()->cursorRectangle().center();
        self.focalPoint = QPointF(touchPoint.x(), cursorCenter.y());
    } else {
        QPointF cursorCenter = qApp->inputMethod()->cursorRectangle().center();
        platformInputContext()->setSelectionOnFocusObject(touchPoint, cursorCenter);
        QPointF anchorCenter = qApp->inputMethod()->anchorRectangle().center();
        self.focalPoint = QPointF(touchPoint.x(), anchorCenter.y());
    }
}

- (void)selectionChanged
{
    if (!hasSelection()) {
        _cursorLayer.visible = NO;
        _anchorLayer.visible = NO;
        return;
    }

    _cursorLayer.cursorRectangle = toCGRect(qApp->inputMethod()->cursorRectangle());
    _anchorLayer.cursorRectangle = toCGRect(qApp->inputMethod()->anchorRectangle());
    _cursorLayer.visible = YES;
    _anchorLayer.visible = YES;

    if (self.state == UIGestureRecognizerStatePossible) {
        // Since we are in UIGestureRecognizerStatePossible, it means  that
        // the selection didn't come from the user dragging on the handles.
        // In that case, we show the edit menu.
        if (QIOSTextInputOverlay::s_editMenu.willHide)
            QIOSTextInputOverlay::s_editMenu.reshowAfterDidHide = YES;
        else
            QIOSTextInputOverlay::s_editMenu.visible = YES;
    }
}

@end

// -------------------------------------------------------------------------

/**
  This recognizer will trigger if the user taps inside the edit rectangle.
  If the tap doesn't result in the cursor changing position, the visibility
  of the edit menu will be toggled.
  */
@interface QIOSOpenMenuOnTapRecognizer : UITapGestureRecognizer {
    int _cursorPosOnPress;
    UIView *_focusView;
}
@end

@implementation QIOSOpenMenuOnTapRecognizer

- (id)init
{
    if (self = [super initWithTarget:self action:@selector(gestureStateChanged)]) {
        self.enabled = NO;
    }

    return self;
}

- (void)setEnabled:(BOOL)enabled
{
    if (enabled == self.enabled)
        return;

    [super setEnabled:enabled];

    if (enabled) {
        _focusView = [reinterpret_cast<UIView *>(qApp->focusWindow()->winId()) retain];
        [_focusView addGestureRecognizer:self];
    } else {
        [_focusView removeGestureRecognizer:self];
        [_focusView release];
        _focusView = nil;
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    _cursorPosOnPress = QInputMethod::queryFocusObject(Qt::ImCursorPosition, QVariant()).toInt();
    [super touchesBegan:touches withEvent:event];

    QPointF touchPos = fromCGPoint([static_cast<UITouch *>([touches anyObject]) locationInView:_focusView]);
    QTransform tf = QGuiApplication::inputMethod()->inputItemTransform();
    QRectF inputRect = tf.mapRect(QGuiApplication::inputMethod()->inputItemRectangle());
    if (!inputRect.contains(touchPos))
        self.state = UIGestureRecognizerStateFailed;
}

- (void)gestureStateChanged
{
    if (self.state != UIGestureRecognizerStateEnded)
        return;

    // The edit menu hides when tapping outside it. Since this happens just before we recognize
    // a tap, we need to check for this since we don't want to reshow the menu in that case.
    if (QIOSTextInputOverlay::s_editMenu.willHide)
        return;

    int currentCursorPos = QInputMethod::queryFocusObject(Qt::ImCursorPosition, QVariant()).toInt();
    if (currentCursorPos == _cursorPosOnPress)
        QIOSTextInputOverlay::s_editMenu.visible = !QIOSTextInputOverlay::s_editMenu.visible;
}

@end

// -------------------------------------------------------------------------

QT_BEGIN_NAMESPACE

QIOSEditMenu *QIOSTextInputOverlay::s_editMenu = Q_NULLPTR;

QIOSTextInputOverlay::QIOSTextInputOverlay()
    : m_timerId(0)
    , m_cursorRecognizer(Q_NULLPTR)
    , m_selectionRecognizer(Q_NULLPTR)
    , m_openMenuOnTapRecognizer(Q_NULLPTR)
{
    connect(qApp, &QGuiApplication::focusObjectChanged, this, &QIOSTextInputOverlay::updateFocusObject);
    connect(qApp->inputMethod(), &QInputMethod::cursorRectangleChanged, this, &QIOSTextInputOverlay::updateSelection);
    connect(qApp->inputMethod(), &QInputMethod::anchorRectangleChanged, this, &QIOSTextInputOverlay::updateSelection);
}

QIOSTextInputOverlay::~QIOSTextInputOverlay()
{
    disconnect(qApp, 0, this, 0);
    disconnect(qApp->inputMethod(), 0, this, 0);
}

void QIOSTextInputOverlay::updateFocusObject()
{
    if (m_cursorRecognizer) {
        // Destroy old recognizers since they were created with
        // dependencies to the old focus object (focus view).
        m_cursorRecognizer.enabled = NO;
        m_selectionRecognizer.enabled = NO;
        m_openMenuOnTapRecognizer.enabled = NO;
        [m_cursorRecognizer release];
        [m_selectionRecognizer release];
        [m_openMenuOnTapRecognizer release];
        [s_editMenu release];
        m_cursorRecognizer = Q_NULLPTR;
        m_selectionRecognizer = Q_NULLPTR;
        m_openMenuOnTapRecognizer = Q_NULLPTR;
        s_editMenu = Q_NULLPTR;
    }

    if (platformInputContext()->inputMethodAccepted()) {
        s_editMenu = [QIOSEditMenu new];
        m_cursorRecognizer = [QIOSCursorRecognizer new];
        m_selectionRecognizer = [QIOSSelectionRecognizer new];
        m_openMenuOnTapRecognizer = [QIOSOpenMenuOnTapRecognizer new];
        m_cursorRecognizer.enabled = YES;
        m_selectionRecognizer.enabled = YES;
        m_openMenuOnTapRecognizer.enabled = YES;
    }
}

void QIOSTextInputOverlay::updateSelection()
{
    // We start a timer, since we often get update signals for both the cursor and the
    // anchor at the same time, and we might also change any of them as a response.
    if (!m_timerId)
        m_timerId = startTimer(1);
}

void QIOSTextInputOverlay::timerEvent(QTimerEvent *)
{
    killTimer(m_timerId);
    m_timerId = 0;
    if (m_selectionRecognizer)
        [m_selectionRecognizer selectionChanged];
}

QT_END_NAMESPACE
