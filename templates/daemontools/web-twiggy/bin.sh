#!/bin/sh
exec 2>&1
#export PLACK_ENV=hoge

eval "exec setuidgid @@USER@@ \
    @@ROOT@@/plackup -p @@PORT@@ $PLACK_COMMAND_LINE_ARGS \
    @@ROOT@@/bin/server.psgi"
