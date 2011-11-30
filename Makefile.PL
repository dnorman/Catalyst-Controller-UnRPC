#!/usr/bin/env perl
# IMPORTANT: if you delete this file your app will not work as
# expected.  You have been warned.
use inc::Module::Install;

name 'Catalyst-Controller-UnRPC';
all_from 'lib/Catalyst/Controller/UnRPC.pm';

requires 'parent';
requires 'Catalyst::Controller';
requires 'Pod::JSchema';
requires 'JSON';
requires 'JSON::XS';
requires 'Moose';

WriteAll;
