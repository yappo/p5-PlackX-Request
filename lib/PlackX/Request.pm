package PlackX::Request;
use Any::Moose;
use HTTP::Headers;
use URI::QueryParam;
BEGIN { require Carp }; # do not call Carp->import for performance

use Socket qw[AF_INET inet_aton]; # for _build_hostname
use PlackX::Request::Upload;
use URI;
use URI::WithBase;

our $VERSION = '0.01';

sub BUILDARGS {
    my($class, $env, %args) = @_;
    {
        env           => $env,
        %args,
    };
}

has env => (
    is       => 'ro',
    isa      => 'HashRef',
    required => 1,
);

sub BUILD {
    my ( $self, $param ) = @_;

    foreach my $field qw(base path) {
        if ( my $val = $param->{$field} ) {
            $self->$field($val);
        }
    }
}

sub address     { $_[0]->env->{REMOTE_ADDR} }
sub protocol    { $_[0]->env->{SERVER_PROTOCOL} }
sub method      { $_[0]->env->{REQUEST_METHOD} }
sub port        { $_[0]->env->{SERVER_PORT} }
sub user        { $_[0]->env->{REMOTE_USER} }
sub request_uri { $_[0]->env->{REQUEST_URI} }

has cookies => (
    is      => 'rw',
    isa     => 'HashRef',
    lazy_build => 1,
);

sub _build_cookies {
    my $self = shift;
    require CGI::Simple::Cookie;

    if (my $header = $self->header('Cookie')) {
        return { CGI::Simple::Cookie->parse($header) };
    } else {
        return {};
    }
}

has query_parameters => (
    is      => 'rw',
    isa     => 'HashRef',
    lazy_build => 1,
);

sub _build_query_parameters {
    my $self = shift;
    $self->uri->query_form_hash;
}

# https or not?
has secure => (
    is      => 'rw',
    isa     => 'Bool',
    lazy_build => 1,
);

sub _build_secure {
    my $self = shift;

    if ( $self->env->{'psgi.url_scheme'} eq 'https' ) {
        return 1;
    }

    return 1 if $self->port == 443;
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

has _body_parser => (
    is      => 'ro',
    isa     => 'PlackX::Request::BodyParser',
    lazy_build => 1,
);

sub _build__body_parser {
    my $self = shift;
    require PlackX::Request::BodyParser;
    PlackX::Request::BodyParser->new( $self->env );
}

has raw_body => (
    is      => 'rw',
    isa     => 'Str',
    lazy_build => 1,
);

sub _build_raw_body {
    my $self = shift;
    $self->_body_parser->raw_body($self);
}

has headers => (
    is      => 'rw',
    isa => 'HTTP::Headers',
    lazy_build => 1,
    handles => [ qw(content_encoding content_length content_type header referer user_agent) ],
);

sub _build_headers {
    my ($self, ) = @_;

    my $env = $self->env;

    HTTP::Headers->new(
        map {
            (my $field = $_) =~ s/^HTTPS?_//;
            ( $field => $env->{$_} );
        }
        grep { /^(?:HTTP|CONTENT|COOKIE)/i } keys %$env
    );
}

has hostname => (
    is      => 'rw',
    isa     => 'Str',
    lazy_build => 1,
);

sub _build_hostname {
    my ( $self, ) = @_;
    $self->env->{REMOTE_HOST} || $self->_resolve_hostname;
}

sub _resolve_hostname {
    my ( $self, ) = @_;
    gethostbyaddr( inet_aton( $self->address ), AF_INET );
}
# for win32 hacks
BEGIN {
    if ($^O eq 'MSWin32') {
        no warnings 'redefine';
        *_build_hostname = sub {
            my ( $self, ) = @_;
            my $address = $self->address;
            return 'localhost' if $address eq '127.0.0.1';
            return gethostbyaddr( inet_aton( $address ), AF_INET );
        };
    }
}

has http_body => (
    is         => 'rw',
    isa        => 'HTTP::Body',
    lazy_build => 1,
    handles => {
        body_parameters => 'param',
        body            => 'body',
    },
);

sub _build_http_body {
    my $self = shift;
    $self->_body_parser->http_body();
}

# contains body_params and query_params
has parameters => (
    is      => 'rw',
    isa     => 'HashRef',
    lazy_build => 1,
);

sub _build_parameters {
    my $self = shift;

    my $query = $self->query_parameters;
    my $body = $self->body_parameters;

    my %merged;

    foreach my $hash ( $query, $body ) {
        foreach my $name ( keys %$hash ) {
            my $param = $hash->{$name};
            push( @{ $merged{$name} ||= [] }, ( ref $param ? @$param : $param ) );
        }
    }

    foreach my $param ( values %merged ) {
        $param = $param->[0] if @$param == 1;
    }

    return \%merged;
}

has uploads => (
    is      => 'rw',
    isa     => 'HashRef',
    lazy_build => 1,
);

sub _build_uploads {
    my $self = shift;
    my $uploads = $self->http_body->upload;
    my %uploads;
    for my $name (keys %{ $uploads }) {
        my $files = $uploads->{$name};
        $files = ref $files eq 'ARRAY' ? $files : [$files];

        my @uploads;
        for my $upload (@{ $files }) {
            my $headers = HTTP::Headers->new( %{ $upload->{headers} } );
            push(
                @uploads,
                PlackX::Request::Upload->new(
                    headers  => $headers,
                    tempname => $upload->{tempname},
                    size     => $upload->{size},
                    filename => $upload->{filename},
                )
            );
        }
        $uploads{$name} = @uploads > 1 ? \@uploads : $uploads[0];

        # support access to the filename as a normal param
        my @filenames = map { $_->{filename} } @uploads;
        $self->parameters->{$name} =  @filenames > 1 ? \@filenames : $filenames[0];
    }
    return \%uploads;
}

# aliases
*body_params  = \&body_parameters;
*input        = \&body;
*params       = \&parameters;
*query_params = \&query_parameters;
*path_info    = \&path;

sub cookie {
    my $self = shift;

    return keys %{ $self->cookies } if @_ == 0;

    if (@_ == 1) {
        my $name = shift;
        return undef unless exists $self->cookies->{$name}; ## no critic.
        return $self->cookies->{$name};
    }
    return;
}

sub param {
    my $self = shift;

    return keys %{ $self->parameters } if @_ == 0;

    if (@_ == 1) {
        my $param = shift;
        return wantarray ? () : undef unless exists $self->parameters->{$param};

        if ( ref $self->parameters->{$param} eq 'ARRAY' ) {
            return (wantarray)
              ? @{ $self->parameters->{$param} }
                  : $self->parameters->{$param}->[0];
        } else {
            return (wantarray)
              ? ( $self->parameters->{$param} )
                  : $self->parameters->{$param};
        }
    } else {
        my $field = shift;
        $self->parameters->{$field} = [@_];
    }
}

sub upload {
    my $self = shift;

    return keys %{ $self->uploads } if @_ == 0;

    if (@_ == 1) {
        my $upload = shift;
        return wantarray ? () : undef unless exists $self->uploads->{$upload};

        if (ref $self->uploads->{$upload} eq 'ARRAY') {
            return (wantarray)
              ? @{ $self->uploads->{$upload} }
          : $self->uploads->{$upload}->[0];
        } else {
            return (wantarray)
              ? ( $self->uploads->{$upload} )
          : $self->uploads->{$upload};
        }
    } else {
        while ( my($field, $upload) = splice(@_, 0, 2) ) {
            if ( exists $self->uploads->{$field} ) {
                for ( $self->uploads->{$field} ) {
                    $_ = [$_] unless ref($_) eq "ARRAY";
                    push(@{ $_ }, $upload);
                }
            } else {
                $self->uploads->{$field} = $upload;
            }
        }
    }
}

has uri => (
    is     => 'rw',
    isa => 'URI::WithBase',
    lazy_build => 1,
    handles => [qw(base path)],
);

sub _build_uri  {
    my($self, ) = @_;

    my $env = $self->env;

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
    $uri->scheme($env->{'psgi.url_scheme'});
    $uri->host($env->{HTTP_HOST}   || $env->{SERVER_NAME});
    $uri->port($env->{SERVER_PORT});
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

sub uri_with {
    my($self, $args) = @_;
    
    Carp::carp( 'No arguments passed to uri_with()' ) unless $args;

    for my $value (values %{ $args }) {
        next unless defined $value;
        for ( ref $value eq 'ARRAY' ? @{ $value } : $value ) {
            $_ = "$_";
            utf8::encode( $_ );
        }
    };
    
    my $uri = $self->uri->clone;
    
    $uri->query_form( {
        %{ $uri->query_form_hash },
        %{ $args },
    } );
    return $uri;
}

sub absolute_url {
    my ($self, $location) = @_;

    unless ($location =~ m!^https?://!) {
        return URI->new( $location )->abs( $self->base );
    } else {
        return $location;
    }
}

sub as_http_request {
    my $self = shift;
    require 'HTTP/Request.pm'; ## no critic
    HTTP::Request->new( $self->method, $self->uri, $self->headers, $self->raw_body );
}

sub as_string {
    my $self = shift;
    $self->as_http_request->as_string; # FIXME not efficient
}

sub content {
    my ( $self, @args ) = @_;

    if ( @args ) {
        Carp::croak "The HTTP::Request method 'content' is unsupported when used as a writer, use PlackX::RequestBuilder";
    } else {
        return $self->raw_body;
    }
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
