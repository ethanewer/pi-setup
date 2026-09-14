# kedge-fairway build-time helper: the public GitHub mirror of gallery-dl
# omits 8 extractor modules that the released wheel still ships and that
# gallery_dl/extractor/__init__.py still enumerates.  Supplying them as empty
# modules lets the project's own test suite import cleanly; they contribute no
# extractor classes, so extractor discovery is unaffected.
import importlib.abc
import importlib.util
import sys
import types

_MISSING = frozenset((
    "exhentai", "nhentai", "hitomi", "hdoujin",
    "hentaifoundry", "hentaihand", "hentainexus", "schalenetwork",
))


class _StubLoader(importlib.abc.Loader):

    def create_module(self, spec):
        module = types.ModuleType(spec.name)
        module.__package__ = "gallery_dl.extractor"
        module.__doc__ = "stub for an extractor module absent from the mirror"
        module.__path__ = []
        return module

    def exec_module(self, module):
        pass


class _StubFinder(importlib.abc.MetaPathFinder):

    def find_spec(self, fullname, path=None, target=None):
        if fullname.startswith("gallery_dl.extractor."):
            name = fullname.rsplit(".", 1)[1]
            if name in _MISSING:
                return importlib.util.spec_from_loader(fullname, _StubLoader())
        return None


sys.meta_path.insert(0, _StubFinder())