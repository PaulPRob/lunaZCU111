"""lunaGUI entry point."""
from __future__ import annotations

import os
import signal
import sys


def apply_style(app) -> None:
    """Compact font: --font-size PT or LUNA_GUI_FONT, default 2 pt below the desktop's."""
    size = os.environ.get("LUNA_GUI_FONT")
    if "--font-size" in sys.argv[:-1]:
        size = sys.argv[sys.argv.index("--font-size") + 1]
    f = app.font()
    try:
        pt = float(size) if size else max(7.0, f.pointSizeF() - 2)
    except ValueError:
        pt = max(7.0, f.pointSizeF() - 2)
    f.setPointSizeF(pt)
    app.setFont(f)


def main() -> int:
    from PyQt6.QtCore import QTimer
    from PyQt6.QtWidgets import QApplication

    from .mainwin import MainWindow

    app = QApplication(sys.argv)
    app.setApplicationName("lunaGUI")
    apply_style(app)
    w = MainWindow()
    # Ctrl-C in the terminal: the timer lets the Python signal handler run
    signal.signal(signal.SIGINT, lambda *_: w.close())
    tick = QTimer()
    tick.timeout.connect(lambda: None)
    tick.start(250)
    w.show()
    if "--plots" in sys.argv:
        w._open_plots()
    if "--spectrum" in sys.argv:
        w._open_spectrum()
    if "--connect" in sys.argv:
        w._toggle_connect()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
