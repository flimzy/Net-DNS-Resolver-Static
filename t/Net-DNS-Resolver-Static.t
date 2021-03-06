#!/usr/bin/perl
use strict;
use warnings;
use lib 't';

use Test::More tests => 25;
use Test::Exception;

BEGIN { use_ok('Net::DNS::Resolver::Static') };

throws_ok { Net::DNS::Resolver::Static->new() } qr/No static cache provided/;

{
    my $res = bless {}, 'Net::DNS::Resolver::Static';

    lives_ok { $res->_populate_static_cache('') };
    dies_ok { $res->_populate_static_cache('bogus data') } qr/Cache syntax error/;
}

{   # Test that string parsing works
    my $res;

    ok( $res = Net::DNS::Resolver::Static->new( static_data => '
        a.com.  3600    IN      A   1.2.3.4
        b.com   IN  A   1.2.3.4
    '));
    is_deeply( $res->{static_dns}, {
        'b.com. IN A' => ['b.com   IN  A   1.2.3.4'],
        'a.com. IN A' => ['a.com.  3600    IN      A   1.2.3.4']
    } )
};

{   # Test that file parsing works
    my $res;

    ok( $res = Net::DNS::Resolver::Static->new( static_file => './t/dns-cache.txt' ));
    is_deeply( $res->{static_dns}, {
        'y.com. IN A' => [ undef ],
        'z.com. IN A' => [ 'z.com.  3600    IN  A   5.4.3.2' ],
        'x.com. IN A' => [ 'error "Foo error"' ]
    } );
};

{
    my $res = Net::DNS::Resolver::Static->new( static_data => '
        a.com.  IN  A   1.2.3.4
    ');
    ok( $res->send('a.com'), 'Test that trailing . is added for lookup');
    my $packet;
    ok( $packet = $res->send('a.com.'), 'Basic lookup returns an answer');
    is( scalar $packet->answer, 1, 'a.com. has one answer' );
    my ( $rr ) = $packet->answer;
    is( $rr->ttl, 0, 'a.com. IN A TTL as expected');
    is( $rr->type, 'A', 'a.com. IN A type as expected' );
    is( $rr->class, 'IN', 'a.com. IN A class as expected' );
    is( $rr->address, '1.2.3.4', 'a.com. IN A address as expected' );
};

{
    my $res = Net::DNS::Resolver::Static->new( static_data => '
        b.com.  IN  A   error "Foo error"
    ');
    ok( ! $res->send('b.com'), 'Test that error is cached' );
    is( $res->errorstring, 'Foo error', 'Error message as expected' );
}

{
    my $res = Net::DNS::Resolver::Static->new( static_data => '
        c.com.  IN  A   ; No record
    ');
    my $packet;
    ok( $packet = $res->send('c.com'), 'Test for negative result' );
    is( scalar $packet->answer, 0, 'No results for c.com. IN A');
}

{   # Test NXDOMAIN
    my $res = Net::DNS::Resolver::Static->new( static_data => 'perl.test. IN A error "NXDOMAIN"' );

    ok( ! $res->query('perl.test'), "No response to perl.test query");
}

{   # Test a PTR CNAME
    my $res = Net::DNS::Resolver::Static->new( static_data => '
        165.51.128.66.in-addr.arpa.         IN      CNAME   165.160/27.51.128.66.in-addr.arpa.
        165.160/27.51.128.66.in-addr.arpa.  IN      PTR     mail.theartfarm.com.
    ');

    my $packet;
    ok( $packet = $res->send('66.128.51.165') );
    is( scalar($packet->answer), 2, "Expecting two answers for CNAME");
}

{   # Test bgsend and bgread
    my $res;
    ok( $res = Net::DNS::Resolver::Static->new( static_data => '
        a.com.  3600    IN      A   1.2.3.4
    '));
    my $socket = $res->bgsend('a.com.');
    ok( $socket, 'bgsend result is truthy');
    my $packet = $res->bgread( $socket );
    is( scalar( $packet->answer),1,'Expected one answer from bgread');
}
