package PlackX::Request::BodyParser;
use Any::Moose;

use HTTP::Body;
use HTTP::Engine::Request::Upload;

# by HTTP::Engine::Role::RequestBuilder::HTTPBody

# tempolary file path for upload file.
has upload_tmp => (
    is => 'rw',
);

has chunk_size => (
    is      => 'ro',
    isa     => 'Int',
    default => 4096,
);

sub http_body {
    my ( $self, ) = @_;

    $self->_read_to_end();
    return $self->_http_body;
}

sub raw_body {
    my ( $self, ) = @_;

    $self->_read_to_end();
    return $self->_raw_body;
}

has 'content_length' => (
    is => 'ro',
    isa => 'Int',
    required => 1,
);

has 'content_type' => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has _http_body => (
    is => 'ro',
    isa => 'HTTP::Body',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $body = HTTP::Body->new($self->content_type, $self->content_length);
        $body->tmpdir( $self->upload_tmp) if $self->upload_tmp;
        $body;
    },
);

has _read_position => (
    is  => 'ro',
    isa => 'Int',
    default => 0,
);

sub BUILDARGS {
    my ( $class, $env ) = @_;
    +{
        content_length       => $env->{'CONTENT_LENGTH'},
        content_type         => $env->{'CONTENT_TYPE'},
        input_handle         => $env->{'psgi.input'},
    };
}

has 'input_handle' => (
    is => 'ro',
    required => 1,
);

has _raw_body => (
    is => 'ro',
    isa => 'Str',
    lazy_build => 1,
);

# by HTTP::Engine::Role::RequestBuilder::ReadBody

sub _read_to_end {
    my ( $self, ) = @_;

    my $content_length = $self->content_length;

    if ($content_length > 0) {
        while (my $buffer = $self->_read() ) {
            $self->{_raw_body} .= $buffer;
            $self->_http_body->add($buffer);
        }

        # paranoia against wrong Content-Length header
        my $diff = $content_length - $self->_read_position;

        if ($diff != 0) {
            if ( $diff > 0) {
                die "Wrong Content-Length value: " . $content_length;
            } else {
                die "Premature end of request body, $diff bytes remaining";
            }
        }
    }
}

sub _read {
    my ($self, ) = @_;

    my $remaining = $self->content_length() - $self->_read_position();

    my $maxlength = $self->chunk_size;

    # Are we done reading?
    if ($remaining <= 0) {
        return;
    }

    my $readlen = ($remaining > $maxlength) ? $maxlength : $remaining;

    my $rc = $self->input_handle->read(my $buffer, $readlen);

    if (defined $rc) {
        $self->{_read_position} += $rc;
        return $buffer;
    } else {
        die "Unknown error reading input: $!";
    }
}

1;

