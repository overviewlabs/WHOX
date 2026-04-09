"""Compatibility package for legacy ``hermes_cli`` imports.

WHOX renamed the CLI package to ``whox_cli``. Some older skills/scripts may
still import modules via ``hermes_cli.*`` (for example
``hermes_cli.tools_config``). This shim keeps those imports working by
re-exporting ``whox_cli`` and sharing its package path.
"""

from whox_cli import *  # noqa: F401,F403
from whox_cli import __path__ as _whox_cli_path

# Let ``import hermes_cli.<module>`` resolve modules from ``whox_cli``.
__path__ = list(_whox_cli_path)

