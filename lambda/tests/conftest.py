"""
pytest configuration for lambda/tests/

Each test module imports its Lambda handler as `import handler as h`, but all
three Lambdas live in different directories and share the module name "handler".
Python's module cache means sys.modules["handler"] ends up pointing to the last
one imported.

This conftest restores sys.modules["handler"] to the handler expected by each
test before the test runs, so that patch("handler.xxx") targets the correct
Lambda module.
"""

import sys
import pytest


@pytest.fixture(autouse=True)
def _restore_handler_module(request):
    """Point sys.modules['handler'] at the handler belonging to this test module."""
    h = getattr(request.module, "h", None)
    if h is not None:
        sys.modules["handler"] = h
    yield
