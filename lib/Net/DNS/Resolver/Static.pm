package Net::DNS::Resolver::Static;

use strict;
use warnings;

use base 'Net::DNS::Resolver';
use Net::IP;
use Socket;
use Storable qw(freeze thaw);

our $VERSION = '0.01';

sub new {
    my ( $class, %args ) = @_;
    my $static_data = delete $args{static_data};
    my $static_file = delete $args{static_file};

    my $self = $class->SUPER::new( %args );

    my $package = __PACKAGE__;

    if ( $static_file ) {
        open my $F, '<', $static_file
            or die "$package: FATAL: Unable to open '$static_file': $!\n";
        local $/;
        my $data = <$F>;
        close $F;
        eval { $self->_populate_static_cache($data) };
        if ( $@ ) {
            die "$package: FATAL: Error reading '$static_file': $@";
        }
    }
    if ( $static_data ) {
        eval { $self->_populate_static_cache($static_data) };
        if ( $@ ) {
            die "$package: FATAL: $@";
        }
    }
    if ( ! $self->{static_dns} ) {
        die "$package: FATAL: No static cache provided";
    }
    $self->{_bg_queue} = [];
    return $self;
}

sub _populate_static_cache {
    my ( $self, $data ) = @_;
    my $line_num = 0;
    for my $line (split /\n/,$data) {
        $line_num++;
        $line =~ s/;.*//;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next if $line =~ /^$/;
        my ( $host, $class, $type, $value )
            = $line =~ /^\s*([\/_a-z\.0-9-]+)\s+(?:\d+\s+)?([A-Z]+)\s+([A-Z]+)\b\s*([^\s].*)?/;
        if ( ! $host ) {
            die "Cache syntax error, $line_num: $line\n";
        }
        $line = $value if defined $value and $value =~ /^error\s/;
        if ( $host !~ /\.$/ ) {
            $host .= '.';
        }
        push @{ $self->{static_dns}{"$host $class $type"} ||= [] }, ( $value ? $line : undef );
    }
}

sub send {
    my ( $self, $host, $type, $class ) = @_;
    $class ||= 'IN';
    if ( ! $type ) {
        if ( Net::IP::ip_is_ipv4($host) ) {
            $type = 'PTR';
            $host = Net::IP::ip_reverse($host,32,4);
        } elsif ( Net::IP::ip_is_ipv6($host) ) {
            $type = 'PTR';
            $host = Net::IP::ip_reverse($host,128,6);
        } else {
            $type = 'A';
        }
    }
    if ( $host !~ /\.$/ ) {
        $host .= '.';
    }

    my $cached_record;
    if ( exists $self->{static_dns}{"$host $class $type"} ) {
        # If we have an exact match, use it
        $cached_record = $self->{static_dns}{"$host $class $type"};
    } elsif ( exists $self->{static_dns}{"$host $class CNAME"} ) {
        # If there's no exact match, look for a CNAME match
        $cached_record = $self->{static_dns}{"$host $class CNAME"};
    } else {
        # Finally, issue an error and die
        $self->_cache_miss($host,$class,$type);
    }
    if ( defined $cached_record->[0] and $cached_record->[0] =~ /^error\s+"(.*)"$/ ) {
        $self->{errorstring} = $1;
        return;
    }
    my $packet = Net::DNS::Packet->new($host,$type,$class);
    if ( defined $cached_record ) {
        $packet->push( answer =>
            map { Net::DNS::RR->new( $_ ) }
            grep { $_ }
            @$cached_record );
    }
    for my $rr ( $packet->answer ) {
        if ( $rr->type eq 'CNAME' ) {
            my $subpacket = $self->send($rr->cname,$type,$class);
            for my $subrr ( $subpacket->answer ) {
                $packet->push( answer => $subrr );
            }
        }
    }
    return $packet;
}

sub _cache_miss {
    my ( $self, $host, $class, $type ) = @_;
    my $package = __PACKAGE__;
    warn <<EOF;
!!!! $package !!!!
No cached answer available for '$host $class $type'
EOF
    die "Dying\n";  # Net::DNS::Async captures $@, so we don't see the 'die' output
                    # in some caess, so we display all the useful info in the warning
                    # instead
}

# This implementation of bgsend/bgread is super ugly, but it works. We do nothing
# in the background, and we actually violate the API contract for bgsend() specified
# in the Net::DNS::Resolver docs by returning an answer packet rather than a socket
# but as of this writing, it works just fine, as Net::DNS::Resolver apparently
# makes no effort to ensure that a socket is returned. So we just return the ansewr
# then bgread echoes it back to the caller.

sub bgsend {
    return shift->send( @_ );
}

sub bgread {
    shift;
    return shift;
}


1;
__END__

=head1 NAME

Net::DNS::Resolver::Static - Static DNS resolver class

=head1 SYNOPSIS

  use Net::DNS::Resolver::Static;

  # Initiate your resolver object with pre-defined DNS answers
  my $res = Net::DNS::Resolver::Static->new( static_data => '
          a.com.        IN  A   1.2.3.4
          b.com. 3600   IN  MX  mail.b.com.
      ' );

  # Or point to a file containing your DNS answers
  my $res = Net::DNS::Resolver::Static->new(
      static_file => './t/dns-cache.txt')

  # Then use it just like Net::DNS::Resolver

  my $answer = $res->query('example.com','MX');

=head1 DESCRIPTION

This is a subclass of L<Net::DNS::Resolver> which reads all DNS answers
from a provided static string or file, rather than from the network. It
is designed for the purpose of unit testing code which uses
L<Net::DNS::Resolver>.

This module overloads the ->new() method and the ->send() methods of
L<Net::DNS::Resolver>.

=head1 SEE ALSO

As this is only a minimal sublass of <Net::DNS::Resolver>, you should
generally refer to the documentation for L<Net::DNS::Resolver> and
its related modules for full functionality.

=head1 AUTHOR

Jonathan Hall E<lt>flimzy@flimzy.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by Jonathan Hall

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
