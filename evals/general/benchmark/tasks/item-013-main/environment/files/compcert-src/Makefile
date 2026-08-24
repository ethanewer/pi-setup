.PHONY: all load verify oextract backend clean

all:
	$(MAKE) load
	$(MAKE) verify
	$(MAKE) oextract
	$(MAKE) backend

load:
	./configure

verify:
	@cd build && COQC="$$(command -v coqc 2>/dev/null)"; \
	if [ -z "$$COQC" ]; then COQC="$$(find /usr /opt -name coqc 2>/dev/null | head -1)"; fi; \
	if [ -z "$$COQC" ]; then echo "verify: coqc not found (apt install coq)" >&2; exit 1; fi; \
	"$$COQC" ../cert/cert.v && touch cert.checked

oextract:
	@cd build && OCAMLC="$$(command -v ocamlc 2>/dev/null)"; \
	if [ -z "$$OCAMLC" ]; then OCAMLC="$$(find /usr /opt -name ocamlc 2>/dev/null | head -1)"; fi; \
	if [ -z "$$OCAMLC" ]; then echo "oextract: ocamlc not found (apt-get install ocaml)" >&2; exit 1; fi; \
	"$$OCAMLC" -c ../src/stamp.ml && touch oextract.checked

backend:
	@CC="$$(command -v gcc 2>/dev/null)"; \
	if [ -z "$$CC" ]; then CC="$$(find /usr /opt -name gcc 2>/dev/null | head -1)"; fi; \
	"$$CC" -O1 -Ibuild -o build/c0 src/ccomp.c

clean:
	rm -rf build/c0 build/*.checked build/cfg.mk build/deploy.h