#!/usr/bin/env python3
"""ConfGen Standalone Runner."""

import os
import sys

# Ensure repository root is in sys.path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from confgen.cli import main

if __name__ == "__main__":
    sys.exit(main())
