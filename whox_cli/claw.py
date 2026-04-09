"""WHOX claw command shim."""


def claw_command(args):
    """Disable migration commands in WHOX distributions."""
    _ = args
    print("Claw migration commands are disabled in WHOX")
