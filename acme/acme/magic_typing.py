"""Simple shim around the typing module.

This was useful when this code supported Python 2 and typing wasn't always
available. This code is being kept for now for backwards compatibility.

"""
from typing import *  # pylint: disable=wildcard-import, unused-wildcard-import
from typing import Collection, IO  # type: ignore


class TypingClass:
    """Ignore import errors by getting anything"""
    def __getattr__(self, name):
        return None  # pragma: no cover
