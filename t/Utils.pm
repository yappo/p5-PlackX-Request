package t::Utils;
use Any::Moose;
use PlackX::Request;

use base qw/Exporter/;

our @EXPORT = qw/ req /;

sub req {
    my %args = @_;

    open my $in, '<', \do { my $d };
    my $env = {
        'psgi.version'    => [ 1, 0 ],
        'psgi.input'      => $in,
        'psgi.errors'     => *STDERR,
        'psgi.url_scheme' => ($ENV{HTTPS}||'off') =~ /^(?:on|1)$/i ? 'https' : 'http',
        %ENV,
        %{ delete($args{env}) || +{} },
    };
    PlackX::Request->new($env, %args);
}

1;
