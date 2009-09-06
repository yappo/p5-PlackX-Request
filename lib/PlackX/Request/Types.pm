package PlackX::Request::Types;
use Any::Moose;
use Any::Moose (
    'X::Types'        => [-declare => [qw/Uri/]],
    'X::Types::'.any_moose() , [qw/HashRef Str Object CodeRef ArrayRef/],
);

use URI;
use URI::WithBase;
use URI::QueryParam;

# Types
do {
    subtype Uri, as "URI::WithBase";

    coerce Uri, from Str, via {

        # generate base uri                                                                                             
        my $uri  = URI->new($_);
        my $base = $uri->path;
        $base =~ s{^/+}{};
        $uri->path($base);
        $base .= '/' unless $base =~ /\/$/;
        $uri->query(undef);
        $uri->path($base);
        URI::WithBase->new( $_, $uri );
    };
};

1;

