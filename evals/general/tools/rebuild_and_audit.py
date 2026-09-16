#!/usr/bin/env python3
"""Compatibility entry point for shared candidate QA; never regenerates tasks."""
from qa_task import main

if __name__ == '__main__':
    raise SystemExit(main())
