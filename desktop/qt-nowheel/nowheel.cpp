// BreezeNoWheel: Breeze, except that the mouse wheel over a combo box, spin box or slider that does
// not have the keyboard focus scrolls the view around it instead of changing the control's value
// (KDE bug 399324; Qt has no switch for spin boxes and sliders). Clicking or tabbing to a control
// gives it the focus, and then the wheel changes it as before. Scroll bars keep their wheel.
// The style it wraps is LINUX_LAB_NOWHEEL_BASE when set (the tests use Fusion), else Breeze.
#include <QAbstractSlider>
#include <QAbstractSpinBox>
#include <QComboBox>
#include <QEvent>
#include <QProxyStyle>
#include <QScrollBar>
#include <QStyleFactory>
#include <QStylePlugin>

namespace {

bool takesWheelOnlyFocused(const QWidget *w)
{
    return qobject_cast<const QComboBox *>(w) || qobject_cast<const QAbstractSpinBox *>(w)
        || (qobject_cast<const QAbstractSlider *>(w) && !qobject_cast<const QScrollBar *>(w));
}

class NoWheelStyle : public QProxyStyle
{
public:
    explicit NoWheelStyle(QStyle *base)
        : QProxyStyle(base)
    {
    }

    void polish(QWidget *w) override
    {
        QProxyStyle::polish(w);
        if (takesWheelOnlyFocused(w)) {
            // Without WheelFocus, the wheel no longer hands the control the focus on its way in.
            if (w->focusPolicy() & Qt::WheelFocus)
                w->setFocusPolicy(Qt::StrongFocus);
            w->installEventFilter(this);
        }
    }

    void unpolish(QWidget *w) override
    {
        if (takesWheelOnlyFocused(w))
            w->removeEventFilter(this);
        QProxyStyle::unpolish(w);
    }

    void polish(QPalette &p) override { QProxyStyle::polish(p); }
    void polish(QApplication *a) override { QProxyStyle::polish(a); }

    bool eventFilter(QObject *o, QEvent *e) override
    {
        if (e->type() == QEvent::Wheel) {
            auto *w = static_cast<QWidget *>(o);
            if (!w->hasFocus()) {
                e->ignore(); // handled here, not accepted: Qt offers it to the parents, the view among them
                return true;
            }
        }
        return QProxyStyle::eventFilter(o, e);
    }
};

class NoWheelPlugin : public QStylePlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QStyleFactoryInterface_iid FILE "nowheel.json")

public:
    QStyle *create(const QString &key) override
    {
        if (key.compare(QLatin1String("BreezeNoWheel"), Qt::CaseInsensitive) != 0)
            return nullptr;
        const QString base = qEnvironmentVariable("LINUX_LAB_NOWHEEL_BASE", QStringLiteral("Breeze"));
        QStyle *s = QStyleFactory::create(base);
        return s ? new NoWheelStyle(s) : nullptr; // no Breeze: Qt falls back to its default style
    }
};

} // namespace

#include "nowheel.moc"
