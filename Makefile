SHELL := /bin/bash
GLOSA_TEST_BASH ?= bash
BASHES ?= /bin/bash $(firstword $(wildcard /opt/homebrew/bin/bash /usr/local/bin/bash) $(shell command -v bash))
LINT_FILES := glosa.sh test/test_helper.bash test/support/*.bash $(wildcard test/*.bats) $(wildcard bench/*.sh)

.PHONY: test test-all lint bench

test:
	GLOSA_TEST_BASH=$(GLOSA_TEST_BASH) bats test

# Runs the suite once per bash in $(BASHES); bats itself runs under that bash
# because a symlink named "bash" is put first on PATH.
test-all:
	@set -e; for b in $(BASHES); do \
	    dir="$$(mktemp -d)"; ln -s "$$b" "$$dir/bash"; \
	    echo "==> $$("$$b" -c 'echo $$BASH_VERSION') ($$b)"; \
	    PATH="$$dir:$$PATH" GLOSA_TEST_BASH="$$b" bats test || { rm -rf "$$dir"; exit 1; }; \
	    rm -rf "$$dir"; \
	done

lint:
	shellcheck -x $(LINT_FILES)

bench:
	bash bench/bench.sh
