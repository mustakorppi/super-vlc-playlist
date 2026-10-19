# SPDX-License-Identifier: GPL-2.0-only
# Copyright and licensing scope: see COPYRIGHT.md in the project root.
from pathlib import Path
import sys
from helper.worker import execute

if __name__ == '__main__':
    execute(Path(sys.argv[1]))
