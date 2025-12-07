# Makefile
# Convenience targets. The tool itself is just ./curve-text.sh.

ITEMS ?= items.json
OUT   ?= out

.PHONY: render one lint test clean

render:
	./curve-text.sh "$(ITEMS)" "$(OUT)"

# render a single item for quick iteration: make one N=2
one:
	./curve-text.sh "$(ITEMS)" "$(OUT)" --only "$(N)"

lint:
	shellcheck curve-text.sh lib/*.sh

test:
	bats tests/

clean:
	rm -rf "$(OUT)" tmp
