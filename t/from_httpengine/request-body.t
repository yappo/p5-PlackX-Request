use strict;
use warnings;
use Test::More tests => 2;
use t::Utils;
use IO::Scalar;
use HTTP::Request;

# prepare
my $body = 'foo=bar';
tie *STDIN, 'IO::Scalar', \$body;
$ENV{CONTENT_LENGTH} = length($body);
$ENV{CONTENT_TYPE}   = 'application/x-www-form-urlencoded';
$ENV{REQUEST_METHOD} = 'POST';
$ENV{SCRIPT_NAME}    = '/';

# do test
do {
    my $req = req;
    is $req->raw_body, 'foo=bar';
    is_deeply $req->body_params, { foo => 'bar' };
};

