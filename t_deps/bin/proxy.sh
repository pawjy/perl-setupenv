#!/bin/sh
tdeps=`dirname $0`/..
port=16613
kill `cat $tdeps/proxy.pid`
echo $$ > $tdeps/proxy.pid
exec perl $tdeps/modules/perl-anyevent-httpserver/bin/proxy.pl $port
