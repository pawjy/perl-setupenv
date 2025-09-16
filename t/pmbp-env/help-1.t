#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl

if [ -n "$TRAVIS" ]; then
  sudo apt-get install -y perl-doc
fi

((perl $pmbp --help > /dev/null) || echo "not ok 1") && echo "ok 1"
#XXX
((PMBP_VERBOSE=10 perl $pmbp --help-tutorial > /dev/null) || echo "not ok 2") && echo "ok 2"
((perl $pmbp --version > /dev/null) || echo "not ok 3") && echo "ok 3"
