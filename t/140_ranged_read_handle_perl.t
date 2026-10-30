use strict;
use warnings;

use Test::More tests => 3;
use Ceph::Rados;
use Ceph::Rados::Striper;

{ package FakeHandle; sub new { bless { buf => '' } } sub write { $_[0]{buf} .= $_[1] } }

my @rnd = ('a'..'z',0..9);
my $pool = $ENV{CEPH_POOL} || 'test_' . join '', map { $rnd[rand @rnd] } 0..9;
my $client = $ENV{CEPH_CLIENT} || 'admin';
my $soid = "test_ranged.$$";
my $chunk = 1024 * 1024;

my $pool_created_p = system "ceph osd pool create $pool 1"
    unless $ENV{CEPH_POOL};
SKIP: {
    skip "Can't create $pool pool", 3 if $pool_created_p;

    my $cluster = Ceph::Rados->new($client);
    $cluster->set_config_file;
    $cluster->set_config_option(keyring => "/etc/ceph/ceph.client.$client.keyring");
    $cluster->connect;
    my $striper = Ceph::Rados::Striper->new($cluster->io($pool));

    my $data = ('a' x $chunk) . ('b' x $chunk);
    ok( $striper->write($soid, $data), "Write $soid" );

    my $handle = FakeHandle->new;
    is( $striper->read_handle($soid, $handle, $chunk, $chunk), $chunk,
        "Ranged read_handle_perl returns requested length" );
    is( $handle->{buf}, 'b' x $chunk, "Ranged read returns second chunk" );

    $striper->remove($soid);
    system "ceph osd pool delete $pool $pool --yes-i-really-really-mean-it"
        unless $ENV{CEPH_POOL};
}
