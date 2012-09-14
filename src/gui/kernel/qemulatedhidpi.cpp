#include "qemulatedhidpi_p.h"

bool qt_use_emulated_hidpi_mode = false;
const qreal qt_emulated_scale_factor = 2.0;

void qhidpiSetEmulationEnabled(bool enable)
{
    qt_use_emulated_hidpi_mode = enable;
}

bool qhidpiIsEmulationEnabled()
{
    return qt_use_emulated_hidpi_mode;
}

QRect qhidpiPixelToPoint(const QRect &pixelRect)
{
    if (!qt_use_emulated_hidpi_mode)
        return pixelRect;

    return QRect(pixelRect.topLeft() / qt_emulated_scale_factor, pixelRect.size() / qt_emulated_scale_factor);
}

QRect qhidpiPointToPixel(const QRect &pointRect)
{
    if (!qt_use_emulated_hidpi_mode)
        return pointRect;

    return QRect(pointRect.topLeft() * qt_emulated_scale_factor, pointRect.size() * qt_emulated_scale_factor);
}

QRectF qhidpiPixelToPoint(const QRectF &pixelRect)
{
    if (!qt_use_emulated_hidpi_mode)
        return pixelRect;

    return QRectF(pixelRect.topLeft() / qt_emulated_scale_factor, pixelRect.size() / qt_emulated_scale_factor);
}

QRectF qhidpiPointToPixel(const QRectF &pointRect)
{
    if (!qt_use_emulated_hidpi_mode)
        return pointRect;

    return QRectF(pointRect.topLeft() * qt_emulated_scale_factor, pointRect.size() * qt_emulated_scale_factor);
}

QSize qhidpiPixelToPoint(const QSize &pixelSize)
{
    if (!qt_use_emulated_hidpi_mode)
        return pixelSize;

    return pixelSize / qt_emulated_scale_factor;
}

QSize qhidpiPointToPixel(const QSize &pointSize)
{
    if (!qt_use_emulated_hidpi_mode)
        return pointSize;

    return pointSize * qt_emulated_scale_factor;
}

QSizeF qhidpiPixelToPoint(const QSizeF &pixelSize)
{
    if (!qt_use_emulated_hidpi_mode)
        return pixelSize;

    return pixelSize / qt_emulated_scale_factor;
}

QSizeF qhidpiPointToPixel(const QSizeF &pointSize)
{
    if (!qt_use_emulated_hidpi_mode)
        return pointSize;

    return pointSize * qt_emulated_scale_factor;
}

QPoint qhidpiPixelToPoint(const QPoint &pixelPoint)
{
    if (!qt_use_emulated_hidpi_mode)
        return pixelPoint;

    return pixelPoint / qt_emulated_scale_factor;
}

QPoint qhidpiPointToPixel(const QPoint &pointPoint)
{
    if (!qt_use_emulated_hidpi_mode)
        return pointPoint;

    return pointPoint * qt_emulated_scale_factor;
}

QPointF qhidpiPixelToPoint(const QPointF &pixelPoint)
{
    if (!qt_use_emulated_hidpi_mode)
        return pixelPoint;

    return pixelPoint / qt_emulated_scale_factor;
}

QPointF qhidpiPointToPixel(const QPointF &pointPoint)
{
    if (!qt_use_emulated_hidpi_mode)
        return pointPoint;

    return pointPoint * qt_emulated_scale_factor;
}

QMargins qhidpiPixelToPoint(const QMargins &pixelMargins)
{
    if (!qt_use_emulated_hidpi_mode)
        return pixelMargins;

    return QMargins(pixelMargins.left() / qt_emulated_scale_factor, pixelMargins.top() / qt_emulated_scale_factor,
                    pixelMargins.right() / qt_emulated_scale_factor, pixelMargins.bottom() / qt_emulated_scale_factor);
}

QMargins qhidpiPointToPixel(const QMargins &pointMargins)
{
    if (!qt_use_emulated_hidpi_mode)
        return pointMargins;

    return QMargins(pointMargins.left() * qt_emulated_scale_factor, pointMargins.top() * qt_emulated_scale_factor,
                    pointMargins.right() * qt_emulated_scale_factor, pointMargins.bottom() * qt_emulated_scale_factor);
}

QRegion qhidpiPixelToPoint(const QRegion &pixelRegion)
{
    return pixelRegion; // ### figure it out
}

QRegion qhidpiPointToPixel(const QRegion &pointRegion)
{
    return pointRegion; // ### figure it out
}
