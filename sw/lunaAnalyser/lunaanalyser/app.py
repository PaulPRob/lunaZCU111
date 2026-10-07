"""lunaAnalyser: step through recorded events (.npz) and plot them as lunaGUI does.

examples
  lunaAnalyser                         # reopens the last directory
  lunaAnalyser data/run_20261007_101500
  lunaAnalyser -d data -r              # all runs below data/
  lunaAnalyser data/run1 -i -1         # start at the last file
"""
from __future__ import annotations

import argparse
import signal
import sys


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="lunaAnalyser", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("directory", nargs="?", help="directory of event files (.npz)")
    ap.add_argument("-d", "--dir", dest="dir_opt", metavar="DIR",
                    help="directory of event files (same as the positional argument)")
    ap.add_argument("-r", "--recursive", action=argparse.BooleanOptionalAction, default=None,
                    help="include subdirectories (default: as last time)")
    ap.add_argument("-i", "--index", type=int, default=None,
                    help="file number to show first (1 = first, -1 = last)")
    args, qt_args = ap.parse_known_args(sys.argv[1:] if argv is None else argv)

    from PyQt6.QtCore import QTimer
    from PyQt6.QtWidgets import QApplication

    from .mainwin import AnalyserWindow

    app = QApplication([sys.argv[0]] + qt_args)
    app.setApplicationName("lunaAnalyser")
    w = AnalyserWindow(args.dir_opt or args.directory, args.recursive, args.index)
    # Ctrl-C in the terminal: the timer lets the Python signal handler run
    signal.signal(signal.SIGINT, lambda *_: w.close())
    tick = QTimer()
    tick.timeout.connect(lambda: None)
    tick.start(250)
    w.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
