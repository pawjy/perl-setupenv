## This is an example Makefile.

PERL = perl
PERL_VERSION = latest
PERL_PATH = $(abspath local/perlbrew/perls/perl-$(PERL_VERSION)/bin)
REMOTEDEV_HOST = remotedev.host.example
REMOTEDEV_PERL_VERSION = $(PERL_VERSION)

Makefile-setupenv: Makefile.setupenv
	$(MAKE) --makefile Makefile.setupenv setupenv-update \
	    SETUPENV_MIN_REVISION=20120313

Makefile.setupenv:
	wget -O $@ https://raw.github.com/wakaba/perl-setupenv/master/Makefile.setupenv

local-perl perl-version perl-exec \
local-submodules config/perl/libs.txt \
carton-install carton-update carton-install-module \
remotedev-test remotedev-reset remotedev-reset-setupenv \
generatepm: %: Makefile-setupenv
	$(MAKE) --makefile Makefile.setupenv $@ \
            REMOTEDEV_HOST=$(REMOTEDEV_HOST) \
            REMOTEDEV_PERL_VERSION=$(REMOTEDEV_PERL_VERSION)

# ------ Examples of rules using Makefile.setup rules ------

PROVE = prove

test: local-submodules carton-install config/perl/libs.txt
	PATH=$(PERL_PATH):$(PATH) PERL5LIB=$(shell cat config/perl/libs.txt) \
	    $(PROVE) t/*.t

GENERATEPM = local/generatepm/bin/generate-pm-package

dist:
	$(GENERATEPM) config/dist/hogehoge.pi dist/
