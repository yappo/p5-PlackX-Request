package PlackX::Request::BodyParser;
use Any::Moose;

use HTTP::Body;
use HTTP::Engine::Request::Upload;

#has 'req' => (
#    is       => 'ro',
#    isa      => 'PlackX::Request',
#    required => 1,
#    weak_ref => 1,
#);

# tempolary file path for upload file.
has upload_tmp => (
    is => 'rw',
);

has chunk_size => (
    is      => 'ro',
    isa     => 'Int',
    default => 4096,
);


sub _build_raw_body {
    my ( $self, $req ) = @_;

    $self->_read_to_end($req->_read_state);

    return delete $req->_read_state->{data}{raw_body};
}

sub _build_read_state {
    my($self, $req) = @_;

    my $length = $req->content_length || 0;
    my $type   = $req->header('Content-Type');

    my $body = HTTP::Body->new($type, $length);
    $body->tmpdir( $self->upload_tmp) if $self->upload_tmp;

    return $self->_read_init({
        input_handle   => $req->_connection->{input_handle},
        content_length => $length,
        read_position  => 0,
        data => {
            raw_body      => "",
            http_body     => $body,
        },
    });
}

sub _handle_read_chunk {
    my ( $self, $state, $chunk ) = @_;

    my $d = $state->{data};

    $d->{raw_body} .= $chunk;
    $d->{http_body}->add($chunk);
}


# by HTTP::Engine::Role::RequestBuilder::ReadBody
sub _read_init {
    my ( $self, $read_state ) = @_;

    foreach my $key qw(input_handle content_length) {
        Carp::confess "read initialization must set $key"
            unless defined $read_state->{$key};
    }

    return $read_state;
}

sub _read_start {
    my ( $self, $state ) = @_;
    $state->{started} = 1;
}

sub _read_to_end {
    my ( $self, $state, @args ) = @_;

    my $content_length = $state->{content_length};

    if ($content_length > 0) {
        $self->_read_all($state, @args);

        # paranoia against wrong Content-Length header
        my $diff = $state->{content_length} - $state->{read_position};

        if ($diff) {
            if ( $diff > 0) {
                die "Wrong Content-Length value: " . $content_length;
            } else {
                die "Premature end of request body, $diff bytes remaining";
            }
        }
    }
}

sub _read_all {
    my ( $self, $state ) = @_;

    while (my $buffer = $self->_read($state) ) {
        $self->_handle_read_chunk($state, $buffer);
    }
}

sub _read {
    my ($self, $state) = @_;

    $self->_read_start($state) unless $state->{started};

    my ( $length, $pos ) = @{$state}{qw(content_length read_position)};

    my $remaining = $length - $pos;

    my $maxlength = $self->chunk_size;

    # Are we done reading?
    if ($remaining <= 0) {
        return;
    }

    my $readlen = ($remaining > $maxlength) ? $maxlength : $remaining;

    my $rc = $self->_read_chunk($state, my $buffer, $readlen);

    if (defined $rc) {
        $state->{read_position} += $rc;
        return $buffer;
    } else {
        die "Unknown error reading input: $!";
    }
}

sub _read_chunk {
    my ( $self, $state ) = ( shift, shift );

    my $handle = $state->{input_handle};

    $self->_io_read( $handle, @_ );
}

sub _io_read {
    my ( $self, $handle ) = ( shift, shift );

    Carp::confess "no handle" unless defined $handle;

    return $handle->read(@_);
}

1;

