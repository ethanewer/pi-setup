"""Protected member inherited through the MRO, read via self.__class__."""


class Base:
    _plan = {"name": "base", "steps": 3}


class Derived(Base):
    _extra = None

    def build(self):
        """self.__class__ is Derived; inherited _plan and own _extra are silent."""
        steps = self.__class__._plan["steps"] + 1
        return self.__class__._extra, steps