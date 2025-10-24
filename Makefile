SHELL := /bin/bash

.PHONY: .rocks
.rocks: graphql-scm-1.rockspec Makefile
		tt rocks make
		tt rocks install luatest 0.5.7
		tt rocks install luacov 0.13.0
		tt rocks install luacheck 0.26.0

.PHONY: lint
lint:
		if [ ! -d ".rocks" ]; then make .rocks; fi
		.rocks/bin/luacheck .

.PHONY: test
test:
		if [ ! -d ".rocks" ]; then make .rocks; fi
		rm -f tmp/luacov*
		.rocks/bin/luatest --verbose --coverage --shuffle group
		.rocks/bin/luacov . && grep -A999 '^Summary' tmp/luacov.report.out

.PHONY: clean
clean:
		rm -rf .rocks

.PHONY: build
build:	
		if [ ! -d ".rocks" ]; then make .rocks; fi
		tt rocks pack graphql scm-1	
