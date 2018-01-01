#!/bin/sh
echo "1..2"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir/foo

if [ $TRAVIS != "" ] && [ $TRAVIS_OS_NAME == "osx" ]; then
  echo "Travis CI (Mac OS X)"
  export HOMEBREW_NO_AUTO_UPDATE=1
  brew install coreutils || true
  
  ## This waits for user's input permanently...
  cd $tempdir/foo && \
  gtimeout 120 perl $pmbp --install-commands docker
  echo "ok 1"

  (open /Applications/Docker.app && echo "ok 2") || echo "not ok 2"
else
  cd $tempdir/foo && \
  ((perl $pmbp --install-commands docker && echo "ok 1") || echo "not ok 1")

  (docker --version && echo "ok 2") || echo "not ok 2"
fi

rm -fr $tempdir
