"""Errors surfaced to the user as a non-zero exit with a named field or file."""


class PackagerError(Exception):
    """A rejection: the CLI prints the message and exits non-zero."""
