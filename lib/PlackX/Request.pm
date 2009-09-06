package PlackX::Request;
use Any::Moose;
use HTTP::Headers::Fast;
use URI::QueryParam;
#require Carp; # Carp->import is too heavy =(
use PlackX::Request::Types qw( Uri Header );

our $VERSION = '0.01';

sub BUILDARGS {
    my($class, $env) = @_;
    {
        _connection => {
            env           => $env,
            input_handle  => $env->{'psgi.input'},
            error_handle  => $env->{'psgi.errors'},
        },
    };
}

has _connection => (
    is => "ro",
    isa => 'HashRef',
    required => 1,
);

has connection_info => (
    is => "rw",
    isa => "HashRef",
    lazy_build => 1,
);

sub _build_connection_info {
    my($self, ) = @_;

    my $env = $self->_connection->{env};

    return {
        address      => $env->{REMOTE_ADDR},
        protocol     => $env->{SERVER_PROTOCOL},
        method       => $env->{REQUEST_METHOD},
        port         => $env->{SERVER_PORT},
        user         => $env->{REMOTE_USER},
        _url_scheme  => $env->{'psgi.url_scheme'},
        request_uri  => $env->{REQUEST_URI},
    }
}

foreach my $attr qw(address method protocol user port _url_scheme request_uri) {
    has $attr => (
        is => 'rw',
        # isa => "Str",                                                                                                 
        lazy => 1,
        default => sub { shift->connection_info->{$attr} },
    );
}

# https or not?
has secure => (
    is      => 'rw',
    isa     => 'Bool',
    lazy_build => 1,
);

sub _build_secure {
    my $self = shift;

    if ( $self->_url_scheme eq 'https' ) {
        return 1;
    }

    if ( my $port = $self->port ) {
        return 1 if $port == 443;
    }

    return 0;
}

# proxy request?
has proxy_request => (
    is         => 'rw',
    isa        => 'Str', # TODO: union(Uri, Undef) type
#    coerce     => 1,
    lazy_build => 1,
);

sub _build_proxy_request {
    my $self = shift;
    return '' unless $self->request_uri;                   # TODO: return undef
    return '' unless $self->request_uri =~ m!^https?://!i; # TODO: return undef
    return $self->request_uri;                             # TODO: return URI->new($self->request_uri);
}

has uri => (
    is     => 'rw',
    isa => Uri,
    coerce => 1,
    lazy_build => 1,
    handles => [qw(base path)],
);

sub _build_uri  {
    my($self, ) = @_;

    my $env = $self->_connection->{env};

    my $scheme = $self->secure ? 'https' : 'http';
    my $host   = $env->{HTTP_HOST}   || $env->{SERVER_NAME};
    my $port   = $env->{SERVER_PORT};
    $port = ( $self->secure ? 443 : 80 ) unless $port; # dirty code for coverage_test 

    my $base_path;
    if (exists $env->{REDIRECT_URL}) {
        $base_path = $env->{REDIRECT_URL};
        $base_path =~ s/$env->{PATH_INFO}$// if exists $env->{PATH_INFO};
    } else {
        $base_path = $env->{SCRIPT_NAME} || '/';
    }

    my $path = $base_path . ($env->{PATH_INFO} || '');
    $path =~ s{^/+}{};

    # for proxy request
    $path = $base_path = '/' if $self->proxy_request;

    my $uri = URI->new;
    $uri->scheme($scheme);
    $uri->host($host);
    $uri->port($port);
    $uri->path($path || '/');
    $uri->query($env->{QUERY_STRING}) if $env->{QUERY_STRING};

    # sanitize the URI
    $uri = $uri->canonical;

    # set the base URI
    # base must end in a slash
    $base_path =~ s{^/+}{};
    $base_path .= '/' unless $base_path =~ /\/$/;
    my $base = $uri->clone;
    $base->path_query($base_path);

    return URI::WithBase->new($uri, $base);
}


1;
__END__

=head1 NAME

PlackX::Request - Portable HTTP request object

=head1 SYNOPSIS

    # normally a request object is passed into your handler
    sub handle_request {
        my $req = shift;

   };

=head1 DESCRIPTION

L<PlackX::Request> provides a consistent API for request objects across web
server enviroments.

=head1 METHODS

=head2 new

    PlackX::Request->new( $psgi_env );

=head1 ATTRIBUTES

=over 4

=item address

Returns the IP address of the client.

=item cookies

Returns a reference to a hash containing the cookies

=item method

Contains the request method (C<GET>, C<POST>, C<HEAD>, etc).

=item protocol

Returns the protocol (HTTP/1.0 or HTTP/1.1) used for the current request.

=item request_uri

Returns the request uri (like $ENV{REQUEST_URI})

=item query_parameters

Returns a reference to a hash containing query string (GET) parameters. Values can                                                    
be either a scalar or an arrayref containing scalars.

=item secure

Returns true or false, indicating whether the connection is secure (https).

=item proxy_request

Returns undef or uri, if it is proxy request, uri of a connection place is returned.

=item uri

Returns a URI object for the current request. Stringifies to the URI text.

=item user

Returns REMOTE_USER.

=item raw_body

Returns string containing body(POST).

=item headers

Returns an L<HTTP::Headers> object containing the headers for the current request.

=item base

Contains the URI base. This will always have a trailing slash.

=item hostname

Returns the hostname of the client.

=item http_body

Returns an L<HTTP::Body> object.

=item parameters

Returns a reference to a hash containing GET and POST parameters. Values can
be either a scalar or an arrayref containing scalars.

=item uploads

Returns a reference to a hash containing uploads. Values can be either a
L<PlackX::Request::Upload> object, or an arrayref of
L<PlackX::Request::Upload> objects.

=item content_encoding

Shortcut to $req->headers->content_encoding.

=item content_length

Shortcut to $req->headers->content_length.

=item content_type

Shortcut to $req->headers->content_type.

=item header

Shortcut to $req->headers->header.

=item referer

Shortcut to $req->headers->referer.

=item user_agent

Shortcut to $req->headers->user_agent.

=item cookie

A convenient method to access $req->cookies.

    $cookie  = $req->cookie('name');
    @cookies = $req->cookie;

=item param

Returns GET and POST parameters with a CGI.pm-compatible param method. This 
is an alternative method for accessing parameters in $req->parameters.

    $value  = $req->param( 'foo' );
    @values = $req->param( 'foo' );
    @params = $req->param;

Like L<CGI>, and B<unlike> earlier versions of Catalyst, passing multiple
arguments to this method, like this:

    $req->param( 'foo', 'bar', 'gorch', 'quxx' );

will set the parameter C<foo> to the multiple values C<bar>, C<gorch> and
C<quxx>. Previously this would have added C<bar> as another value to C<foo>
(creating it if it didn't exist before), and C<quxx> as another value for
C<gorch>.

=item path

Returns the path, i.e. the part of the URI after $req->base, for the current request.

=item upload

A convenient method to access $req->uploads.

    $upload  = $req->upload('field');
    @uploads = $req->upload('field');
    @fields  = $req->upload;

    for my $upload ( $req->upload('field') ) {
        print $upload->filename;
    }


=item uri_with

Returns a rewritten URI object for the current request. Key/value pairs
passed in will override existing parameters. Unmodified pairs will be
preserved.

=item as_http_request

convert PlackX::Request to HTTP::Request.

=item $req->absolute_url($location)

convert $location to absolute uri.

=back

=head1 AUTHORS


=head1 THANKS TO

L<Catalyst::Request>

=head1 SEE ALSO

L<HTTP::Request>, L<Catalyst::Request>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
