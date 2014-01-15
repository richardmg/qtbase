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

#include <QtGui/private/qguiapplication_p.h>
#include <QtGui/qtextformat.h>
#include <QtGui/private/qwindow_p.h>
#include <qpa/qplatformintegration.h>

#include "quitextinputview.h"
#include "qiosglobal.h"
#include "qiosinputcontext.h"

static QTextCharFormat *g_markedTextformat;

@interface QUITextPosition : UITextPosition {
    NSUInteger _index;
}

@property (nonatomic) NSUInteger index;
+ (QUITextPosition *)positionWithIndex:(NSUInteger)index;

@end

#pragma mark -

@implementation QUITextPosition
@synthesize index = _index;

+ (QUITextPosition *)positionWithIndex:(NSUInteger)index
{
    QUITextPosition *pos = [[QUITextPosition alloc] init];
    pos.index = index;
    return [pos autorelease];
}

@end

#pragma mark -

@interface QUITextRange : UITextRange {
    NSRange _range;
}

@property (nonatomic) NSRange range;
+ (QUITextRange *)rangeWithNSRange:(NSRange)range;

@end

#pragma mark -

@implementation QUITextRange

@synthesize range = _range;

+ (QUITextRange *)rangeWithNSRange:(NSRange)nsrange {
    QUITextRange *range = [[QUITextRange alloc] init];
    range.range = nsrange;
    return [range autorelease];
}

- (UITextPosition *)start {
    return [QUITextPosition positionWithIndex:self.range.location];
}

- (UITextPosition *)end {
    return [QUITextPosition positionWithIndex:(self.range.location + self.range.length)];
}

- (NSRange) range
{
    return _range;
}

-(BOOL)isEmpty {
    return (self.range.length == 0);
}

@end

#pragma mark -

@implementation QUITextInputView

@synthesize autocapitalizationType;
@synthesize autocorrectionType;
@synthesize enablesReturnKeyAutomatically;
@synthesize keyboardAppearance;
@synthesize keyboardType;
@synthesize returnKeyType;
@synthesize secureTextEntry;
@synthesize inputDelegate;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        m_inputMethodQueryEvent = new QInputMethodQueryEvent(Qt::ImQueryInput);
        if (!g_markedTextformat) {
            // There seems to be no way to query how the preedit text should be drawn. But on iOS7
            // at least, groupTableViewBackgroundColor points to the same color:
            CGFloat r, g, b, a;
            [[UIColor groupTableViewBackgroundColor] getRed:&r green:&g blue:&b alpha:&a];
            g_markedTextformat = new QTextCharFormat();
            g_markedTextformat->setBackground(QColor(r * 255, g * 255, b * 255, a * 255));
        }
    }
    return self;
}

- (void)dealloc
{
    delete m_inputMethodQueryEvent;
    [super dealloc];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    // Note: QIOSInputContext controls our first responder status based on
    // whether or not the keyboard should be open or closed.
    [self updateTextInputTraits];
    return [super becomeFirstResponder];
}

- (BOOL)resignFirstResponder
{
    // Resigning first responed status means that the virtual keyboard was closed, or
    // some other view became first responder. In either case we clear the focus object to
    // avoid blinking cursors in line edits etc:
    QWindow *w = qApp->focusWindow();
    Q_ASSERT([self isFirstResponder]);
    Q_ASSERT(self == reinterpret_cast<QUITextInputView *>(w->handle()->winId()));
    static_cast<QWindowPrivate *>(QObjectPrivate::get(w))->clearFocusObject();
    return [super resignFirstResponder];
}

- (void)updateInputMethodWithQuery:(Qt::InputMethodQueries)query
{
    // TODO: check what changed, and perhaps update delegate if the text was
    // changed from somewhere other than this plugin....

    // Note: This function is called both when as a result of the application changing the
    // input, but also (and most commonly) as a response to us sending QInputMethodQueryEvents.
    // Because of the latter, we cannot call textWill/DidChange here, as that will confuse
    // iOS IM handling, and e.g stop spellchecking from working.
    Q_UNUSED(query);
    Q_ASSERT([self isFirstResponder]);

    QObject *focusObject = QGuiApplication::focusObject();
    if (!focusObject)
        return;

    delete m_inputMethodQueryEvent;
    m_inputMethodQueryEvent = new QInputMethodQueryEvent(Qt::ImQueryInput);
    QCoreApplication::sendEvent(focusObject, m_inputMethodQueryEvent);
}

- (void)reset
{
    Q_ASSERT([self isFirstResponder]);

    [self.inputDelegate textWillChange:self];
    [self setMarkedText:@"" selectedRange:NSMakeRange(0, 0)];
    [self updateInputMethodWithQuery:Qt::ImQueryInput];

    // There seem to be no way to inform that the keyboard needs to update (since
    // text input traits might have changed). As a work-around, we quickly resign
    // first responder status just to reassign it again:
    [super resignFirstResponder];
    [self updateTextInputTraits];
    [super becomeFirstResponder];
    [self.inputDelegate textDidChange:self];
}

- (void)commit
{
    [self.inputDelegate textWillChange:self];
    [self unmarkText];
    [self.inputDelegate textDidChange:self];
}

- (QVariant)imValue:(Qt::InputMethodQuery)query
{
    return m_inputMethodQueryEvent->value(query);
}

-(id<UITextInputTokenizer>)tokenizer
{
    return [[[UITextInputStringTokenizer alloc] initWithTextInput:self] autorelease];
}

-(UITextPosition *)beginningOfDocument
{
    return [QUITextPosition positionWithIndex:0];
}

-(UITextPosition *)endOfDocument
{
    int endPosition = [self imValue:Qt::ImSurroundingText].toString().length();
    return [QUITextPosition positionWithIndex:endPosition];
}

- (void)setSelectedTextRange:(UITextRange *)range
{
    QObject *focusObject = QGuiApplication::focusObject();
    if (!focusObject)
        return;

    QUITextRange *r = static_cast<QUITextRange *>(range);
    QList<QInputMethodEvent::Attribute> attrs;
    attrs << QInputMethodEvent::Attribute(QInputMethodEvent::Selection, r.range.location, r.range.length, 0);
    QInputMethodEvent e(m_markedText, attrs);
    QCoreApplication::sendEvent(focusObject, &e);
}

- (UITextRange *)selectedTextRange {
    int cursorPos = [self imValue:Qt::ImCursorPosition].toInt();
    int anchorPos = [self imValue:Qt::ImAnchorPosition].toInt();
    return [QUITextRange rangeWithNSRange:NSMakeRange(cursorPos, (anchorPos - cursorPos))];
}

- (NSString *)textInRange:(UITextRange *)range
{
    int s = static_cast<QUITextPosition *>([range start]).index;
    int e = static_cast<QUITextPosition *>([range end]).index;
    return [self imValue:Qt::ImSurroundingText].toString().mid(s, e - s).toNSString();
}

- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange
{
    Q_UNUSED(selectedRange);

    QObject *focusObject = QGuiApplication::focusObject();
    if (!focusObject)
        return;

    m_markedText = markedText ? QString::fromNSString(markedText) : QString();

    QList<QInputMethodEvent::Attribute> attrs;
    attrs << QInputMethodEvent::Attribute(QInputMethodEvent::TextFormat, 0, markedText.length, *g_markedTextformat);
    QInputMethodEvent e(m_markedText, attrs);
    QCoreApplication::sendEvent(focusObject, &e);
}

- (void)unmarkText
{
    if (m_markedText.isEmpty())
        return;
    QObject *focusObject = QGuiApplication::focusObject();
    if (!focusObject)
        return;

    QInputMethodEvent e;
    e.setCommitString(m_markedText);
    QCoreApplication::sendEvent(focusObject, &e);

    m_markedText.clear();
}

- (NSComparisonResult)comparePosition:(UITextPosition *)position toPosition:(UITextPosition *)other
{
    int p = static_cast<QUITextPosition *>(position).index;
    int o = static_cast<QUITextPosition *>(other).index;
    if (p > o)
        return NSOrderedAscending;
    else if (p < o)
        return NSOrderedDescending;
    return NSOrderedSame;
}

- (UITextRange *)markedTextRange {
    return m_markedText.isEmpty() ? nil : [QUITextRange rangeWithNSRange:NSMakeRange(0, m_markedText.length())];
}

- (UITextRange *)textRangeFromPosition:(UITextPosition *)fromPosition toPosition:(UITextPosition *)toPosition
{
    Q_UNUSED(fromPosition);
    Q_UNUSED(toPosition);
    int f = static_cast<QUITextPosition *>(fromPosition).index;
    int t = static_cast<QUITextPosition *>(toPosition).index;
    return [QUITextRange rangeWithNSRange:NSMakeRange(f, t - f)];
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position offset:(NSInteger)offset
{
    int p = static_cast<QUITextPosition *>(position).index;
    return [QUITextPosition positionWithIndex:p + offset];
}

- (NSInteger)offsetFromPosition:(UITextPosition *)fromPosition toPosition:(UITextPosition *)toPosition
{
    int f = static_cast<QUITextPosition *>(fromPosition).index;
    int t = static_cast<QUITextPosition *>(toPosition).index;
    return t - f;
}

- (CGRect)firstRectForRange:(UITextRange *)range
{
    Q_UNUSED(range);

    QObject *focusObject = QGuiApplication::focusObject();
    if (!focusObject)
        return CGRectZero;

    // Using a work-around to get the current rect until
    // a better API is in place:
    if (!m_markedText.isEmpty())
        return CGRectZero;

    int cursorPos = [self imValue:Qt::ImCursorPosition].toInt();
    int anchorPos = [self imValue:Qt::ImAnchorPosition].toInt();

    NSRange r = static_cast<QUITextRange*>(range).range;
    QList<QInputMethodEvent::Attribute> attrs;
    attrs << QInputMethodEvent::Attribute(QInputMethodEvent::Selection, r.location, 0, 0);
    QInputMethodEvent e(m_markedText, attrs);
    QCoreApplication::sendEvent(focusObject, &e);
    QRectF startRect = qApp->inputMethod()->cursorRectangle();

    attrs = QList<QInputMethodEvent::Attribute>();
    attrs << QInputMethodEvent::Attribute(QInputMethodEvent::Selection, r.location + r.length, 0, 0);
    e = QInputMethodEvent(m_markedText, attrs);
    QCoreApplication::sendEvent(focusObject, &e);
    QRectF endRect = qApp->inputMethod()->cursorRectangle();

    if (cursorPos != int(r.location + r.length) || cursorPos != anchorPos) {
        attrs = QList<QInputMethodEvent::Attribute>();
        attrs << QInputMethodEvent::Attribute(QInputMethodEvent::Selection, cursorPos, (cursorPos - anchorPos), 0);
        e = QInputMethodEvent(m_markedText, attrs);
        QCoreApplication::sendEvent(focusObject, &e);
    }

    return toCGRect(startRect.united(endRect));
}

- (CGRect)caretRectForPosition:(UITextPosition *)position
{
    Q_UNUSED(position);
    // Assume for now that position is always the same as
    // cursor index until a better API is in place:
    QRectF cursorRect = qApp->inputMethod()->cursorRectangle();
    return toCGRect(cursorRect);
}

- (void)replaceRange:(UITextRange *)range withText:(NSString *)text
{
    QObject *focusObject = QGuiApplication::focusObject();
    if (!focusObject)
        return;

    [self setSelectedTextRange:range];

    QInputMethodEvent e;
    e.setCommitString(QString::fromNSString(text));
    QCoreApplication::sendEvent(focusObject, &e);
}

- (void)setMarkedTextRange:(UITextRange *)range
{
    Q_UNUSED(range);
    qDebug() << __FUNCTION__ << "NOT implemented!";
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position inDirection:(UITextLayoutDirection)direction offset:(NSInteger)offset
{
    Q_UNUSED(position);
    Q_UNUSED(direction);
    Q_UNUSED(offset);
    qDebug() << __FUNCTION__ << "NOT implemented";
    return 0;
}

- (UITextPosition *)positionWithinRange:(UITextRange *)range farthestInDirection:(UITextLayoutDirection)direction
{
    Q_UNUSED(range);
    Q_UNUSED(direction);
    qDebug() << __FUNCTION__ << "NOT implemented";
    return 0;
}

- (UITextRange *)characterRangeByExtendingPosition:(UITextPosition *)position inDirection:(UITextLayoutDirection)direction
{
    Q_UNUSED(position);
    Q_UNUSED(direction);
    qDebug() << __FUNCTION__ << "NOT implemented";
    return 0;
}

- (void)setBaseWritingDirection:(UITextWritingDirection)writingDirection forRange:(UITextRange *)range
{
    Q_UNUSED(writingDirection);
    Q_UNUSED(range);
    qDebug() << __FUNCTION__ << "NOT implemented";
}

- (UITextWritingDirection)baseWritingDirectionForPosition:(UITextPosition *)position inDirection:(UITextStorageDirection)direction
{
    Q_UNUSED(position);
    Q_UNUSED(direction);
    qDebug() << __FUNCTION__ << "NOT implemented";
    return 0;
}

- (UITextPosition *)closestPositionToPoint:(CGPoint)point
{
    Q_UNUSED(point);
    qDebug() << __FUNCTION__ << "NOT implemented";
    return 0;
}

- (UITextPosition *)closestPositionToPoint:(CGPoint)point withinRange:(UITextRange *)range
{
    Q_UNUSED(point);
    Q_UNUSED(range);
    qDebug() << __FUNCTION__ << "NOT implemented";
    return 0;
}

- (UITextRange *)characterRangeAtPoint:(CGPoint)point
{
    Q_UNUSED(point);
    qDebug() << __FUNCTION__ << "NOT implemented";
    return 0;
}

- (void)setMarkedTextStyle:(NSDictionary *)style
{
    Q_UNUSED(style);
    qDebug() << __FUNCTION__ << "NOT implemented";
}

-(NSDictionary *)markedTextStyle
{
    qDebug() << __FUNCTION__ << "NOT implemented";
    return 0;
}

- (BOOL)hasText
{
    return YES;
}

- (void)insertText:(NSString *)text
{
    QString string = QString::fromUtf8([text UTF8String]);

    int key = 0;
    if ([text isEqualToString:@"\n"]) {
        key = (int)Qt::Key_Return;
        if (self.returnKeyType == UIReturnKeyDone)
            [self resignFirstResponder];
    }

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

- (void)updateTextInputTraits
{
    // Ask the current focus object what kind of input it
    // expects, and configure the keyboard appropriately:
    QObject *focusObject = QGuiApplication::focusObject();
    if (!focusObject)
        return;
    QInputMethodQueryEvent queryEvent(Qt::ImEnabled | Qt::ImHints);
    if (!QCoreApplication::sendEvent(focusObject, &queryEvent))
        return;
    if (!queryEvent.value(Qt::ImEnabled).toBool())
        return;

    Qt::InputMethodHints hints = static_cast<Qt::InputMethodHints>(queryEvent.value(Qt::ImHints).toUInt());

    self.returnKeyType = (hints & Qt::ImhMultiLine) ? UIReturnKeyDefault : UIReturnKeyDone;
    self.secureTextEntry = BOOL(hints & Qt::ImhHiddenText);
    self.autocorrectionType = (hints & Qt::ImhNoPredictiveText) ?
                UITextAutocorrectionTypeNo : UITextAutocorrectionTypeDefault;
    self.spellCheckingType = (hints & Qt::ImhNoPredictiveText) ?
                UITextSpellCheckingTypeNo : UITextSpellCheckingTypeDefault;

    if (hints & Qt::ImhUppercaseOnly)
        self.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    else if (hints & Qt::ImhNoAutoUppercase)
        self.autocapitalizationType = UITextAutocapitalizationTypeNone;
    else
        self.autocapitalizationType = UITextAutocapitalizationTypeSentences;

    if (hints & Qt::ImhUrlCharactersOnly)
        self.keyboardType = UIKeyboardTypeURL;
    else if (hints & Qt::ImhEmailCharactersOnly)
        self.keyboardType = UIKeyboardTypeEmailAddress;
    else if (hints & Qt::ImhDigitsOnly)
        self.keyboardType = UIKeyboardTypeNumberPad;
    else if (hints & Qt::ImhFormattedNumbersOnly)
        self.keyboardType = UIKeyboardTypeDecimalPad;
    else if (hints & Qt::ImhDialableCharactersOnly)
        self.keyboardType = UIKeyboardTypeNumberPad;
    else
        self.keyboardType = UIKeyboardTypeDefault;
}

@end
