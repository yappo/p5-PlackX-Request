package PlackX::Request::Types;
use Any::Moose;
use Any::Moose (
    'X::Types'        => [-declare => [qw/Uri Header/]],
    'X::Types::'.any_moose() , [qw/HashRef Str Object CodeRef ArrayRef/],
);

use URI;
use URI::WithBase;
use URI::QueryParam;
use HTTP::Headers;

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

do {
    subtype Header,
        as Object,
        where { $_->isa('HTTP::Headers') };

    coerce Header,
        from ArrayRef, via { HTTP::Headers->new( @{$_} ) };
    coerce Header,
        from HashRef,  via { HTTP::Headers->new( %{$_} ) };
};

1;

