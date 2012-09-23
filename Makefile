all:

deps:

## ------ Tests ------

PROVE = prove

test: test-deps test-startproxy test-main test-stopproxy

test-deps: deps test-proxy-deps

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
	http_proxy=localhost:16613 $(PROVE) --verbose t/pmbp/*.t
