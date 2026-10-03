"""lunaGUI entry point."""
from __future__ import annotations

import signal
import sys


def main() -> int:
    from PyQt6.QtCore import QTimer
    from PyQt6.QtWidgets import QApplication

    from .mainwin import MainWindow

    app = QApplication(sys.argv)
    app.setApplicationName("lunaGUI")
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
