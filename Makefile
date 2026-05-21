# Makefile — convenience entry points for common contributor and release
# tasks. Each target wraps the underlying tool invocation so a contributor
# can clone the repo and have a small known set of verbs to run, instead of
# memorizing the swift / xcodebuild flags spread across CI workflows.
#
# Targets:
#   make build       # build the SPM package (debug)
#   make release     # build the owlwatch binary (release config)
#   make test        # run the SPM test suite in parallel
#   make install     # install owlwatch into PREFIX/bin (default /usr/local)
#   make uninstall   # remove owlwatch from PREFIX/bin
#   make clean       # remove SwiftPM build artifacts

PREFIX ?= /usr/local
DESTDIR ?=
SWIFT  ?= swift

PACKAGE_PATH := packages
RELEASE_BINARY := $(PACKAGE_PATH)/.build/release/owlwatch

.PHONY: build release test install uninstall clean

build:
	$(SWIFT) build --package-path $(PACKAGE_PATH) -c debug

release:
	$(SWIFT) build --package-path $(PACKAGE_PATH) -c release

test:
	$(SWIFT) test --package-path $(PACKAGE_PATH) --parallel

install: release
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -m 0755 "$(RELEASE_BINARY)" "$(DESTDIR)$(PREFIX)/bin/owlwatch"
	@echo "Installed $(DESTDIR)$(PREFIX)/bin/owlwatch"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/owlwatch"
	@echo "Removed $(DESTDIR)$(PREFIX)/bin/owlwatch (if it existed)"

clean:
	rm -rf $(PACKAGE_PATH)/.build
