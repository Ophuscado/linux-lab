#include <QApplication>
#include <QComboBox>
#include <QLineEdit>
#include <QScrollArea>
#include <QScrollBar>
#include <QSlider>
#include <QSpinBox>
#include <QVBoxLayout>
#include <QWindow>
#include <qpa/qwindowsysteminterface.h>
#include <cstdio>
// A view taller than its window, with a line edit (which has the focus), a spin box, a combo box and a slider
// in it. One wheel step down, as the window system delivers it, over each control while it has no focus,
// then over the spin box once it has the focus. Prints each value and how far the view moved.
static QScrollArea *area;
static void wheel(QWidget *w)
{
    QWindow *win = area->windowHandle();
    QPointF local = w->mapTo(area, QPointF(w->width() / 2.0, w->height() / 2.0));
    QWindowSystemInterface::handleWheelEvent(win, local, win->mapToGlobal(local), QPoint(), QPoint(0, -120));
    QCoreApplication::processEvents();
}
int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    if (argc > 1) QApplication::setStyle(argv[1]);
    area = new QScrollArea; auto *inner = new QWidget; auto *lay = new QVBoxLayout(inner);
    auto *edit = new QLineEdit; auto *spin = new QSpinBox; spin->setRange(0, 100); spin->setValue(50);
    auto *combo = new QComboBox; combo->addItems({"a", "b", "c"}); combo->setCurrentIndex(1);
    auto *slider = new QSlider(Qt::Horizontal); slider->setRange(0, 100); slider->setValue(50);
    lay->addWidget(edit); lay->addWidget(spin); lay->addWidget(combo); lay->addWidget(slider); lay->addSpacing(3000);
    area->setWidget(inner); area->resize(300, 300); area->show(); area->activateWindow(); QApplication::setActiveWindow(area);
    QCoreApplication::processEvents(); edit->setFocus();
    auto *bar = area->verticalScrollBar();
    std::printf("style %s\n", qPrintable(QApplication::style()->name()));
    for (QWidget *w : {static_cast<QWidget *>(spin), static_cast<QWidget *>(combo), static_cast<QWidget *>(slider)}) {
        bar->setValue(0); wheel(w);
        std::printf("  %-9s unfocused: spin %d combo %d slider %d, view moved %d\n", w->metaObject()->className(), spin->value(), combo->currentIndex(), slider->value(), bar->value());
    }
    bar->setValue(0); spin->setFocus(); wheel(spin);
    std::printf("  QSpinBox  focused (%d): spin %d, view moved %d\n", spin->hasFocus(), spin->value(), bar->value());
    return 0;
}
