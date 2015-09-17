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

#import <UIKit/UIKit.h>

#include <QtGui/qwindow.h>
#include <QtGui/private/qguiapplication_p.h>
#include <qpa/qplatformtheme.h>

#include "qiosmessagedialog.h"

QIOSMessageDialog::QIOSMessageDialog()
    : m_alertController(0)
{
}

QIOSMessageDialog::~QIOSMessageDialog()
{
    hide();
}

void QIOSMessageDialog::addButton(StandardButton standardButton)
{
    UIAlertActionStyle style;

    switch (standardButton) {
    case No:
    case NoToAll:
    case Abort:
    case Ignore:
    case Close:
    case Cancel:
        style = UIAlertActionStyleCancel;
       break;
    case Discard:
    case Reset:
    case RestoreDefaults:
        style = UIAlertActionStyleDestructive;
       break;
    default:
        style = UIAlertActionStyleDefault;
    }

    const QString label = QGuiApplicationPrivate::platformTheme()->standardButtonText(standardButton);
    UIAlertAction* action = [UIAlertAction actionWithTitle:label.toNSString()
            style:style handler:^(UIAlertAction *) { buttonClicked(standardButton); }];
    [m_alertController addAction:action];
}

void QIOSMessageDialog::buttonClicked(StandardButton standardButton)
{
    hide();
    emit clicked(standardButton, QPlatformDialogHelper::buttonRole(standardButton));
}

void QIOSMessageDialog::exec()
{
    m_eventLoop.exec(QEventLoop::DialogExec);
}

bool QIOSMessageDialog::show(Qt::WindowFlags windowFlags, Qt::WindowModality windowModality, QWindow *parent)
{
    Q_UNUSED(windowFlags);

    const QSharedPointer<QMessageDialogOptions> &options = this->options();
    if (!options)
        return false;

    const QString &lineShift = QStringLiteral("\n\n");
    QString text = options->text();
    if (!options->informativeText().isEmpty())
        text += lineShift + options->informativeText();
    if (!options->detailedText().isEmpty())
        text += lineShift + options->detailedText();

    // Remove HTML tags
    text.replace(QLatin1String("<p>"), QStringLiteral("\n"), Qt::CaseInsensitive);
    text.remove(QRegExp(QStringLiteral("<[^>]*>")));

    if (QSysInfo::MacintoshVersion < QSysInfo::MV_IOS_8_0) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Title"
            message:@"This is the message."
            delegate:nil
            cancelButtonTitle:@"OK"
            otherButtonTitles:nil];
        [alertView show];
    } else {
        if (m_alertController)
            return false;

        m_alertController = [[UIAlertController
            alertControllerWithTitle:options->windowTitle().toNSString()
            message:text.toNSString()
            preferredStyle:windowModality == Qt::ApplicationModal ? UIAlertControllerStyleAlert : UIAlertControllerStyleActionSheet]
            retain];

        qDebug() << "buttons:" << options->standardButtons();
        if (!options->standardButtons()) {
            addButton(StandardButton::Ok);
        } else {
            for (int i = QPlatformDialogHelper::FirstButton; i < QPlatformDialogHelper::LastButton; i<<=1) {
                if (StandardButton(i) & options->standardButtons())
                    addButton(StandardButton(i));
            }
        }

        UIWindow *window = parent ? reinterpret_cast<UIView *>(parent->winId()).window : [UIApplication sharedApplication].keyWindow;
        [window.rootViewController presentViewController:m_alertController animated:YES completion:nil];
    }

    return true;
}

void QIOSMessageDialog::hide()
{
    m_eventLoop.exit();
    [m_alertController dismissViewControllerAnimated:YES completion:nil];
    [m_alertController release];
    m_alertController = 0;
}
