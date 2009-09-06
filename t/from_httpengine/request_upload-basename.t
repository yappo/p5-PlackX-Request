use strict;
use warnings;
use Test::More tests => 1;
use PlackX::Request::Upload;

my $upload = PlackX::Request::Upload->new(
    filename => '/tmp/foo/bar/hoge.txt',
);
is $upload->basename, 'hoge.txt';
