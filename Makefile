# Convenience Makefile wrapping Meson

BUILD_DIR ?= build
APP_VERSION ?= 0.1.7
MAINTAINER_NAME ?= netico
MAINTAINER_EMAIL ?= netico@midala.net
BIN ?= $(BUILD_DIR)/src/hikma
MESON ?= meson

.PHONY: all setup compile run install clean distclean debian

sync_version:
	@echo "Syncing project() version to $(APP_VERSION)"
	@sed -i -E "s/(version: ')[^']+(')/\1$(APP_VERSION)\2/" meson.build

all: compile

setup:
	$(MAKE) sync_version
	$(MESON) setup $(BUILD_DIR)

compile:
	@test -d $(BUILD_DIR) || ( $(MAKE) sync_version && $(MESON) setup $(BUILD_DIR) )
	$(MAKE) sync_version
	$(MESON) compile -C $(BUILD_DIR)

run: compile
	./$(BIN)

install: compile
	$(MESON) install -C $(BUILD_DIR)

clean:
	@test -d $(BUILD_DIR) && $(MESON) compile -C $(BUILD_DIR) --clean || true

distclean:
	rm -rf $(BUILD_DIR)

debian: distclean
	$(MAKE) sync_version
		@ver=$(APP_VERSION); \
		 stamp="$$(date -R)"; \
		 [ -f debian/changelog ] || { mkdir -p debian; echo "hikma ($$ver) unstable; urgency=medium" > debian/changelog; echo "" >> debian/changelog; echo "  * Release $$ver" >> debian/changelog; echo "" >> debian/changelog; name="$${MAINTAINER_NAME:-$(MAINTAINER_NAME)}"; email="$${MAINTAINER_EMAIL:-$(MAINTAINER_EMAIL)}"; echo " -- $$name <$$email>  $$stamp" >> debian/changelog; echo "" >> debian/changelog; }; \
		 first_line=$$(head -n1 debian/changelog 2>/dev/null || echo ""); \
		 if echo "$$first_line" | grep -q "^hikma ($$ver) "; then \
			 echo "Changelog already has version $$ver at top; skipping prepend"; \
		 else \
			 echo "Prepending Debian changelog entry for version $$ver"; \
			 tmp=$$(mktemp); \
			 { \
				 echo "hikma ($$ver) unstable; urgency=medium"; \
				 echo ""; \
				 echo "  * Release $$ver"; \
				 echo ""; \
				 name="$${MAINTAINER_NAME:-$(MAINTAINER_NAME)}"; \
				 email="$${MAINTAINER_EMAIL:-$(MAINTAINER_EMAIL)}"; \
				 echo " -- $$name <$$email>  $$stamp"; \
				 echo ""; \
				 cat debian/changelog; \
			 } > $$tmp; \
			 mv $$tmp debian/changelog; \
		 fi
		@echo "Syncing Debian control maintainer from Makefile variables..."; \
		tmpc=$$(mktemp); \
		name="$${MAINTAINER_NAME:-$(MAINTAINER_NAME)}"; \
		email="$${MAINTAINER_EMAIL:-$(MAINTAINER_EMAIL)}"; \
		sed -E "s/^Maintainer: .*/Maintainer: $$name <$$email>/" debian/control > $$tmpc && mv $$tmpc debian/control
		@echo "Building Debian package..."
		dpkg-buildpackage -us -uc -b
		@echo "Cleaning intermediate Debian artifacts..."; \
		find .. -maxdepth 1 -type f \( -name "*.buildinfo" -o -name "*.changes" -o -name "*.dsc" -o -name "*.deb" \) -print | while read f; do \
			 case "$${f}" in \
				 *dbgsym*.deb) rm -f "$${f}" ;; \
				 ../hikma_*_*.deb) : ;; \
				 *) rm -f "$${f}" ;; \
			 esac; \
		 done
		@echo "Selecting main .deb and copying into project root..."
		@arch=$$(dpkg --print-architecture); ver=$(APP_VERSION); \
		 main=../hikma_$${ver}_$${arch}.deb; \
		 if [ ! -f "$$main" ]; then \
			 echo "Expected $$main not found, picking most recent hikma_*.deb"; \
			 main=$$(ls -1t ../hikma_*_$$arch.deb 2>/dev/null | grep -v dbgsym | head -n1); \
		 fi; \
		 if [ -z "$$main" ] || [ ! -f "$$main" ]; then echo "No .deb found in parent directory"; exit 1; fi; \
		 rm -f ./hikma_*_$$arch.deb; rm -f ./hikma_*_dbgsym_$$arch.deb; \
		 cp -f "$$main" ./; \
		 echo "Created: ./$$(basename "$$main")"; \
		 echo "Final cleanup: remove any remaining non-main artifacts from root and parent"; \
		 find . .. -maxdepth 1 -type f \( -name "*.buildinfo" -o -name "*.changes" -o -name "*.dsc" -o -name "hikma_*_dbgsym_*.deb" \) -exec rm -f {} +
