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

sub _build_http_body {
    my ( $self, $req ) = @_;

    $self->_read_to_end($req->_read_state);

    return delete $req->_read_state->{data}{http_body};
}

sub _build_raw_body {
    my ( $self, $req ) = @_;

    $self->_read_to_end($req->_read_state);

    return delete $req->_read_state->{data}{raw_body};
}

sub _build_read_state {
    my($self, $env) = @_;

    my $length = $env->{'CONTENT_LENGTH'};
    Carp::confess "read initialization must set CONTENT_LENGTH"
        unless defined $length;

    my $type   = $env->{'CONTENT_TYPE'};

    my $body = HTTP::Body->new($type, $length);
    $body->tmpdir( $self->upload_tmp) if $self->upload_tmp;

    my $input_handle = $env->{'psgi.input'};
    Carp::confess "read initialization must set psgi.input"
        unless defined $input_handle;

    return {
        input_handle   => $input_handle,
        content_length => $length,
        read_position  => 0,
        data => {
            raw_body      => "",
            http_body     => $body,
        },
    };
}

sub _handle_read_chunk {
    my ( $self, $state, $chunk ) = @_;

    my $d = $state->{data};

    $d->{raw_body} .= $chunk;
    $d->{http_body}->add($chunk);
}

sub _prepare_uploads  {
    my($self, $req) = @_;

    my $uploads = $req->http_body->upload;
    my %uploads;
    for my $name (keys %{ $uploads }) {
        my $files = $uploads->{$name};
        $files = ref $files eq 'ARRAY' ? $files : [$files];

        my @uploads;
        for my $upload (@{ $files }) {
            my $headers = HTTP::Headers->new( %{ $upload->{headers} } );
            push(
                @uploads,
                HTTP::Engine::Request::Upload->new(
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
        $req->parameters->{$name} =  @filenames > 1 ? \@filenames : $filenames[0];
    }
    return \%uploads;
}


# by HTTP::Engine::Role::RequestBuilder::ReadBody
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

    my $rc = $state->{input_handle}->read(my $buffer, $readlen);

    if (defined $rc) {
        $state->{read_position} += $rc;
        return $buffer;
    } else {
        die "Unknown error reading input: $!";
    }
}

1;

