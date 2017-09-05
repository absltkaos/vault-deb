# This Makefile can be used to create a debian package for any 
# tag in the vault git repository on github. A simple
#
#    $ make
#
# will use the latest tag, but any other tag can be specified using
# the VERSION variable, e.g.
#
#    $ make VERSION=0.3.0
#
# Other variables are available: for instance,
#
#    $ make DISTRO=trusty
#
# can be used to change the target distribution (which defaults to
# the one installed on the build machine).
# Please see README.md for a more detailed description.

BASE_DIR  = $(CURDIR)/pkg
DISTRO   ?= $(shell lsb_release -sc)
REVISION ?= 1~$(DISTRO)1~ev
MODIFIER ?= 
CHANGE   ?= "New upstream release."
DEBUILD_OPTS ?= "-S -sa -us -uc"
PBUILDER ?= cowbuilder
PBUILDER_BASE ?= $$HOME/pbuilder/$(DISTRO)-base.cow
PPA      ?= 

build: build_src
	if [ ! -d "$(PBUILDER_BASE)" ] ; then \
		echo "Creating cowbuilder environment"; \
		mkdir -p $(shell dirname "$(PBUILDER_BASE)"); \
		sudo cowbuilder \
			--create \
			--basepath $(PBUILDER_BASE) \
			--distribution $(DISTRO) \
			--debootstrapopts \
			--arch \
			--debootstrapopts amd64 \
			--extrapackages "debhelper ca-certificates" \
			--components "main universe multiverse restricted"; \
	fi
	mkdir -p $(BASE_DIR)/buildresult
	cd $(BASE_DIR) && sudo $(PBUILDER) --build vault_$(VERSION)-$(REVISION).dsc \
	--basepath=$(PBUILDER_BASE) \
	--buildresult buildresult

build_src: prepare_src 
	cd $(PKG_DIR) && debuild $(DEBUILD_OPTS)

prepare_src: download get_current_version create_upstream_tarball
	rsync -qav --delete debian/ $(PKG_DIR)/debian
	$(eval CREATE = $(shell test -f debian/changelog || echo "--create "))
	test $(CURRENT_VERSION)_ != $(VERSION)-$(REVISION)_ && \
	  debchange -c $(PKG_DIR)/debian/changelog $(CREATE)\
        --package vault \
        --newversion $(VERSION)-$(REVISION) \
        --distribution $(DISTRO) \
        --controlmaint \
        $(CHANGE) || exit 0

create_upstream_tarball: get_new_version
	if [ ! -f pkg/vault_$(VERSION).orig.tar.gz ]; then \
	  rm -rf $(PKG_DIR); \
	  rsync -qav --delete $(BASE_DIR)/ $(PKG_DIR); \
	  tar czf pkg/vault_$(VERSION).orig.tar.gz -C $(BASE_DIR) vault-$(VERSION); \
	fi

download:
	if [ ! -f "$(BASE_DIR)/src/vault_$(VERSION)_linux_amd64.zip" ] ; then \
	  mkdir -p "$(BASE_DIR)/src"; \
	  cd "$(BASE_DIR)/src"; \
	  curl https://releases.hashicorp.com/vault/$(VERSION)/vault_$(VERSION)_linux_amd64.zip > vault_$(VERSION)_linux_amd64.zip; \
	  mkdir -p "$(BASE_DIR)/src/docs"; \
	  cd "$(BASE_DIR)/src/docs"; \
	  for rdoc in CHANGELOG.md README.md LICENSE; do \
	    curl https://raw.githubusercontent.com/hashicorp/vault/master/$$rdoc > $$rdoc; \
	  done; \
	  cd $(BASE_DIR); \
	  unzip src/vault_$(VERSION)_linux_amd64.zip; \
	fi

get_current_version:
	$(eval CURRENT_VERSION = $(shell test -f debian/changelog && \
		dpkg-parsechangelog | grep Version | awk '{print $$2}'))
	@echo "--> Current package version: $(CURRENT_VERSION)"
	
get_new_version:

	$(shell if [ -z "$(VERSION)" ]; then \
		echo You must supply a version; \
		exit 1; \
	fi)
	$(eval PKG_DIR = $(BASE_DIR)/vault-$(VERSION))
	@echo "--> New package version: $(VERSION)-$(REVISION)"

clean:
	rm -rf pkg/*

upload: get_new_version
	@if test -z "$(PPA)"; then echo "Usage: make upload PPA=<user>/<ppa>"; exit 1; fi
	dput -f ppa:$(PPA) $(BASE_DIR)/vault_$(VERSION)-$(REVISION)_source.changes
	cp $(BASE_DIR)/vault-$(VERSION)/debian/changelog debian
