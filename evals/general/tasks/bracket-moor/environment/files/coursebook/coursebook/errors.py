"""Domain exceptions for coursebook."""


class CoursebookError(Exception):
    """Base class for all coursebook domain errors."""


class DuplicateRegistrationError(CoursebookError):
    """A student already holds a registration row for the course."""


class NotFoundError(CoursebookError):
    """A referenced student or course does not exist."""


class NoRegistrationError(CoursebookError):
    """An operation needs a registration row the student does not have."""


class InvalidStateError(CoursebookError):
    """An operation is invalid for the current registration status."""