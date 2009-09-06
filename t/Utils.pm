package t::Utils;
use Any::Moose;
use PlackX::Request;

use base qw/Exporter/;

our @EXPORT = qw/ req /;

sub req {
    my %args = @_;

    my $env = {
        'psgi.version'    => [ 1, 0 ],
        'psgi.input'      => *STDIN,
        'psgi.errors'     => *STDERR,
        'psgi.url_scheme' => ($ENV{HTTPS}||'off') =~ /^(?:on|1)$/i ? 'https' : 'http',
        %ENV,
    };
    PlackX::Request->new($env, %args);
}

1;
