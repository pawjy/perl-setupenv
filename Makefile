## This is an example Makefile.
REMOTEDEV_HOST = remotedev.host.example
REMOTEDEV_PERL_PATH = path/to/remote/server/perl/bin
PERL_PATH = local/dummy/path/to/perl/bin

test: local-submodules carton-install config/perl/libs.txt
	PATH=$(PERL_PATH):$(PATH) PERL5LIB=$(shell cat config/perl/libs.txt) \
	    $(PROVE) t/*.t

Makefile-setupenv: Makefile.setupenv
	make --makefile Makefile.setupenv setupenv-update \
	    SETUPENV_MIN_REVISION=20120310

Makefile.setupenv:
	wget -O $@ https://raw.github.com/wakaba/perl-setupenv/master/Makefile.setupenv

setupenv remotedev-test remotedev-reset remotedev-reset-setupenv \
config/perl/libs.txt \
carton-install carton-update local-submodules: %: Makefile-setupenv
	make --makefile Makefile.setupenv $@ \
            REMOTEDEV_HOST=$(REMOTEDEV_HOST) \
            REMOTEDEV_PERL_PATH=$(REMOTEDEV_PERL_PATH)

always:
