use strict;
use warnings;
use Test::More tests => 7;
use t::Utils;
use HTTP::Engine;
use HTTP::Request;
use CGI::Simple::Cookie;

# exist Cookie header.
do {
    # prepare
    local $ENV{HTTP_COOKIE}    = 'Foo=Bar; Bar=Baz';
    local $ENV{REQUEST_METHOD} = 'GET';
    local $ENV{SCRIPT_NAME}    = '/';

    # do test
    do {
        my $req = req;
	is '2', $req->cookie;
        is $req->cookie('undef'), undef;
        is $req->cookie('undef', 'undef'), undef;
        is $req->cookie('Foo')->value, 'Bar';
        is $req->cookie('Bar')->value, 'Baz';
        is_deeply $req->cookies, {Foo => 'Foo=Bar; path=/', Bar => 'Bar=Baz; path=/'};
    };
};

# no Cookie header
do {
    # prepare
    local $ENV{REQUEST_METHOD} = 'GET';
    local $ENV{SCRIPT_NAME}    = '/';

    # do test
    do {
        my $req = req;
        is_deeply $req->cookies, {};
    };
};

