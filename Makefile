GIT = git

all:

deps:

git-submodules:
	$(GIT) submodule update --init

updatenightly: version/perl.txt version/perl-cpan-path.txt
	perl bin/pmbp.pl --print-openssl-stable-branch > version/openssl-stable-branch.txt
	$(GIT) add version/*.txt

local/cpan-perl.html:
	mkdir -p local
	curl -f -L http://search.cpan.org/dist/perl/ > $@
version/perl.txt: bin/extract-latest-perl-version.pl local/cpan-perl.html
	mkdir -p version
	perl bin/extract-latest-perl-version.pl < local/cpan-perl.html
version/perl-cpan-path.txt: version/perl.txt

## ------ Build ------

lib/perl58perlbrewdeps.pm: Makefile
	echo 'BEGIN {' > $@
	echo '$$INC{"Module/Pluggable.pm"} = 1;' >> $@
	echo '$$INC{"Module/Pluggable/Object.pm"} = 1;' >> $@
	echo '$$INC{"Devel/InnerPackage.pm"} = 1;' >> $@
	echo '}' >> $@
	cat lib/IPC/Cmd.pm >> $@
	curl http://cpansearch.perl.org/src/SIMONW/Module-Pluggable-4.7/lib/Module/Pluggable.pm >> $@
	curl http://cpansearch.perl.org/src/SIMONW/Module-Pluggable-4.7/lib/Module/Pluggable/Object.pm >> $@
	curl http://cpansearch.perl.org/src/SIMONW/Module-Pluggable-4.7/lib/Devel/InnerPackage.pm >> $@

## ------ Tests ------

PROVE = prove

test: test-deps test-main

test-deps: git-submodules deps

test-deps-travis: test-deps
	$(GIT) config --global user.email "temp@travis.test"
	$(GIT) config --global user.name "Travis CI"

test-main:
ifeq "$(TARGET)" ""
	$(PROVE) --verbose t/*/*.t
endif
ifeq "$(TARGET)" "normal"
	$(PROVE) -j1 --verbose t/pmbp/*.t
endif
ifeq "$(TARGET)" "install-1"
	$(PROVE) -j1 --verbose t/pmbp-install-1/*.t
endif
ifeq "$(TARGET)" "update"
	$(PROVE) -j1 --verbose t/pmbp-update/*.t
endif
ifeq "$(TARGET)" "lists"
	$(PROVE) -j1 --verbose t/pmbp-lists/*.t
endif
ifeq "$(TARGET)" "env"
	$(PROVE) -j1 --verbose t/pmbp-env/*.t
endif
ifeq "$(TARGET)" "git"
	$(PROVE) -j1 --verbose t/pmbp-git/*.t
endif
ifeq "$(TARGET)" "scan"
	$(PROVE) -j1 --verbose t/pmbp-scan/*.t
endif
ifeq "$(TARGET)" "perl"
	$(PROVE) --verbose t/pmbp-perl/*.t
endif
ifeq "$(TARGET)" "imagemagick"
	$(PROVE) --verbose t/pmbp-imagemagick/*.t
endif
ifeq "$(TARGET)" "apache"
	$(PROVE) --verbose t/pmbp-apache/*.t
endif
ifeq "$(TARGET)" "modperl"
	$(PROVE) --verbose t/pmbp-modperl/*.t
endif
ifeq "$(TARGET)" "mecab"
	$(PROVE) --verbose t/pmbp-mecab/*.t
endif
ifeq "$(TARGET)" "rrdtool"
	$(PROVE) --verbose t/pmbp-rrdtool/*.t
endif
ifeq "$(TARGET)" "svn"
	$(PROVE) --verbose t/pmbp-svn/*.t
endif
ifeq "$(TARGET)" "tls"
	$(PROVE) --verbose t/pmbp-tls/*.t
endif
