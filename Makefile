all:

deps:

## ------ Tests ------

PROVE = prove

test: test-deps test-main

test-deps: deps

test-main:
	$(PROVE) --verbose t/pmbp/*.t
