#!/bin/sh
pmbp-pre-commands=--install-perl --perl-version=latest
sh `dirname $0`/../pmbp/install-module.sh Image::Magick
