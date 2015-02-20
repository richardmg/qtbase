/****************************************************************************
**
** Copyright (C) 2015 The Qt Company Ltd.
** Contact: http://www.qt.io/licensing/
**
** This file is part of the QtCore module of the Qt Toolkit.
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

#include "qstandardpaths.h"

#ifndef QT_NO_STANDARDPATHS

QT_BEGIN_NAMESPACE

static QString pathForDirectory(NSSearchPathDirectory directory)
{
    return QString::fromNSString(
        [NSSearchPathForDirectoriesInDomains(directory, NSUserDomainMask, YES) lastObject]);
}

static QString bundlePath()
{
    return QString::fromNSString([[NSBundle mainBundle] bundlePath]);
}

QString QStandardPaths::writableLocation(StandardLocation type)
{
    QString location;

    switch (type) {
    case DesktopLocation:
        location = pathForDirectory(NSDesktopDirectory);
        break;
    case DocumentsLocation:
        location = pathForDirectory(NSDocumentDirectory);
        break;
    case FontsLocation:
        location = bundlePath() + QLatin1String("/.fonts");
        break;
    case ApplicationsLocation:
        location = pathForDirectory(NSApplicationDirectory);
        break;
    case MusicLocation:
        location = pathForDirectory(NSMusicDirectory);
        break;
    case MoviesLocation:
        location = pathForDirectory(NSMoviesDirectory);
        break;
    case PicturesLocation:
        location = pathForDirectory(NSPicturesDirectory);
        break;
    case TempLocation:
        location = QString::fromNSString(NSTemporaryDirectory());
        break;
    case HomeLocation:
        location = bundlePath();
        break;
    case AppDataLocation:
    case AppLocalDataLocation:
        location = pathForDirectory(NSApplicationSupportDirectory);
        break;
    case GenericDataLocation:
        location = pathForDirectory(NSDocumentDirectory);
        break;
    case CacheLocation:
    case GenericCacheLocation:
        location = pathForDirectory(NSCachesDirectory);
        break;
    case ConfigLocation:
    case GenericConfigLocation:
    case AppConfigLocation:
        location = pathForDirectory(NSDocumentDirectory);
        break;
    case DownloadLocation:
        location = pathForDirectory(NSDownloadsDirectory);
        break;
    default:
        break;
    }

    switch (type) {
    case RuntimeLocation:
        break;
    default:
        // All other types must return something, so use the document directory
        // as a reasonable fall-back (which will always exist).
        if (location.isEmpty())
            location = pathForDirectory(NSDocumentDirectory);
        break;
    }

    return location;
}

QStringList QStandardPaths::standardLocations(StandardLocation type)
{
    QStringList dirs;

    switch (type) {
    case PicturesLocation:
        dirs << writableLocation(PicturesLocation) << QLatin1String("assets-library:");
        break;
    default:
        dirs << writableLocation(type);
        break;
    }

    return dirs;
}

QT_END_NAMESPACE

#endif // QT_NO_STANDARDPATHS
