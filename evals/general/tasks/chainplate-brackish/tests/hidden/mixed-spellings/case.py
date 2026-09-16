"""type(self) and self.__class__ mixed in one method; other object warns."""


class Registry:
    _defaults = {"ttl": 60}

    def resolve(self, key):
        """Both spellings are equivalent and must be accepted."""
        if type(self)._defaults is self.__class__._defaults:
            return self.__class__._defaults.get(key)
        return None

    def resolve_from(self, source, key):
        """Access through another object's class keeps warning."""
        return source.__class__._defaults.get(key)  # [protected-access]