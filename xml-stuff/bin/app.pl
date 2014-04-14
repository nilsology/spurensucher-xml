#!/usr/bin/env perl
use Dancer;
use blog;

# changing default settings
set server  => 'localhost';
set port    => 61235;

dance;
