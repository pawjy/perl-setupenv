GIT = git

all:

deps:

git-submodules:
	$(GIT) submodule update --init

## ------ Tests ------

PROVE = prove -j4

test: test-deps test-startproxy test-main test-stopproxy

test-deps: git-submodules deps test-proxy-deps

test-proxy-deps:
	perl bin/pmbp.pl \
	    --root-dir-name t_deps/modules/perl-anyevent-httpserver \
	    --install-modules-by-list \
	    --write-libs-txt t_deps/modules/perl-anyevent-httpserver/config/perl/libs.txt

test-startproxy:
	PERL5LIB="`cat t_deps/modules/perl-anyevent-httpserver/config/perl/libs.txt`" sh t_deps/bin/proxy.sh &

test-stopproxy:
	-kill `cat t_deps/proxy.pid`
	-rm t_deps/proxy.pid

test-main:
ifeq "$(TARGET)" ""
	http_proxy=localhost:16613 $(PROVE) --verbose t/pmbp/*.t t/pmbp-perl/*.t
endif
ifeq "$(TARGET)" "normal"
	http_proxy=localhost:16613 $(PROVE) --verbose t/pmbp/*.t
endif
ifeq "$(TARGET)" "perl"
	http_proxy=localhost:16613 $(PROVE) --verbose t/pmbp-perl/*.t
endif
