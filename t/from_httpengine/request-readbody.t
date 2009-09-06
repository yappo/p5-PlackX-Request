use strict;
use warnings;
use Test::More tests => 4;
use t::Utils;

use File::Temp qw/:seekable/;
use HTTP::Engine::Request;


do {
    my $req = req();

    do { 
        local $@;
        eval { $req->_body_parser->_io_read };
        like $@, qr/no handle/;
    };
};

do {
    my $tmp = File::Temp->new(UNLINK => 1);
    $tmp->write("OK!");
    $tmp->flush();
    $tmp->seek(0, File::Temp::SEEK_SET);

    my $env = {%ENV, 'psgi.input' => $tmp};
    my $req = req(
        env => $env,
        headers => {
            'Content-Length' => 3,
        },
    );
    my $state = $req->_read_state;
    my $reset = sub {
        $tmp->seek(0, File::Temp::SEEK_SET);
        $state->{read_position} = 0;
    };

    $req->_body_parser->_read_all($state);
    $reset->();

    read_to_end($req, $state, sub { $state->{read_position}-- }, 'Wrong Content-Length value: 3');
    $reset->();

    read_to_end($req, $state, sub { $state->{read_position}++ }, 'Premature end of request body, -1 bytes remaining');
    $reset->();

    do {
        no strict 'refs';
        no warnings 'redefine';
        *{ref($req->_body_parser) . '::_io_read'} = sub { };
        local $@;
        eval { $req->_body_parser->_read($state); };
        like $@, qr/Unknown error reading input/;
    };
};

sub read_to_end {
    my($req, $state, $code, $re) = @_;
    my $orig = $req->_body_parser->can( '_read_all' );

    no strict 'refs';
    no warnings 'redefine';
    *{ref($req->_body_parser) . '::_read_all'} = sub { $orig->(@_); $code->() };

    local $@;
    eval { $req->_body_parser->_read_to_end($state); };
    like $@, qr/\Q$re\E/, $re;

    *{ref($req->_body_parser) . '::_read_all'} = $orig; # restore
}
