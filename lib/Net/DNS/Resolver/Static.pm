package Net::DNS::Resolver::Static;

use strict;
use warnings;

use base 'Net::DNS::Resolver';
use Net::IP;

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
        if ( Net::IP::ip_is_ipv4($host) or Net::IP::ip_is_ipv6($host) ) {
            $type = 'PTR';
            $host = Net::IP::ip_reverse($host);
        } else {
            $type = 'A';
        }
    }
    if ( $host !~ /\.$/ ) {
        $host .= '.';
    }
    if ( ! exists $self->{static_dns}{"$host $class $type"} ) {
        if ( $type eq 'CNAME' or ! exists $self->{static_dns}{"$host $class CNAME"} ) {
            $self->_cache_miss($host,$class,$type)
        }
        $type = 'CNAME';
    }
    my $cached_record = $self->{static_dns}{"$host $class $type"};
    if ( defined $cached_record->[0] and $cached_record->[0] =~ /^error\s+"(.*)"$/ ) {
        $self->{errorstring} = $1;
        return;
    }
    my $answer = Net::DNS::Packet->new($host,$type,$class);
    if ( defined $cached_record ) {
        $answer->push( answer =>
            map { Net::DNS::RR->new( $_ ) }
            grep { $_ }
            @$cached_record );
    }
    return $answer;
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


1;
__END__

=head1 NAME

Net::DNS::Resolver::Static - Static DNS resolver class

=head1 SYNOPSIS

  use Net::DNS::Resolver::Static './static-dns-cache.txt';

  my $res = Net::DNS::Resolver::Static->new;

  # Then use it just like Net::DNS::Resolver

  my $answer = $res->query('example.com','MX');

=head1 DESCRIPTION

This is a subclass of L<Net::DNS::Resolver> which reads all DNS answers
from a local static file, rather than from the network. It is designed
for the purpose of unit testing code which uses Net::DNS::Resolver.


=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Jonathan Hall, E<lt>jonhall@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by Jonathan Hall

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
