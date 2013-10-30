#!/bin/sh
export pmbp_pre_commands="--install-perl --perl-version=latest"
sh `dirname $0`/../pmbp/install-module.sh Image::Magick
