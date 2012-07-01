## This is an example Makefile.

WGET = wget
PERL = perl
PERL_VERSION = latest
PERL_PATH = $(abspath local/perlbrew/perls/perl-$(PERL_VERSION)/bin)
REMOTEDEV_HOST = remotedev.host.example
REMOTEDEV_PERL_VERSION = $(PERL_VERSION)

# Set git repository URL for CPAN mirror, if exists
PMBUNDLER_REPO_URL = 
PMB_PMTAR_REPO_URL =
PMB_PMPP_REPO_URL = 

Makefile-setupenv: Makefile.setupenv
	$(MAKE) --makefile Makefile.setupenv setupenv-update \
	    SETUPENV_MIN_REVISION=20120338

Makefile.setupenv:
	$(WGET) -O $@ https://raw.github.com/wakaba/perl-setupenv/master/Makefile.setupenv

lperl lplackup local-perl perl-version perl-exec \
local-submodules config/perl/libs.txt \
carton-install carton-update carton-install-module \
remotedev-test remotedev-reset remotedev-reset-setupenv \
pmb-install pmb-update cinnamon \
generatepm: %: Makefile-setupenv
	$(MAKE) --makefile Makefile.setupenv $@ \
            REMOTEDEV_HOST=$(REMOTEDEV_HOST) \
            REMOTEDEV_PERL_VERSION=$(REMOTEDEV_PERL_VERSION) \
	    PMBUNDLER_REPO_URL=$(PMBUNDLER_REPO_URL) \
	    PMB_PMTAR_REPO_URL=$(PMB_PMTAR_REPO_URL) \
	    PMB_PMPP_REPO_URL=$(PMB_PMPP_REPO_URL)

# ------ Examples of rules using Makefile.setup rules ------

PROVE = prove
PERL_ENV = PATH="$(abspath ./local/perl-$(PERL_VERSION)/pm/bin):$(PERL_PATH):$(PATH)" PERL5LIB="$(shell cat config/perl/libs.txt)"

test: local-submodules carton-install config/perl/libs.txt
	$(PERL_ENV) $(PROVE) t/*.t

GENERATEPM = local/generatepm/bin/generate-pm-package

dist: generatepm
	$(GENERATEPM) config/dist/hogehoge.pi dist/
