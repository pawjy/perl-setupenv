#!/bin/bash

if ! curl --version > /dev/null; then
  if apt-get --version > /dev/null; then
    sh -c 'apt-get update && apt-get install -y curl'
  else
    echo "curl not found"
    exit 1
  fi
fi

if ! perl --version > /dev/null; then
  if yum --version > /dev/null; then
    su -c 'yum install -y perl'
  else
    echo "perl not found"
    exit 1
  fi
fi

(mkdir local 2> /dev/null || true) && (mkdir local/bin 2> /dev/null || true) && \
curl -sSLf https://raw.githubusercontent.com/wakaba/perl-setupenv/master/bin/pmbp.pl > local/bin/pmbp.pl.new && \
perl -c local/bin/pmbp.pl.new 2> /dev/null && \
mv local/bin/pmbp.pl.new local/bin/pmbp.pl
