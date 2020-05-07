use strict;
use warnings;

use Test::More tests => 14;
use Test::Exception;
use Ceph::Rados;
use Ceph::Rados::Striper;
use Data::Dump qw/dump/;
use FindBin qw/$Bin/;
use IO::File;

my @rnd = ('a'..'z',0..9);

my $pool = $ENV{CEPH_POOL} || 'test_' . join '', map { $rnd[rand @rnd] } 0..9;

my $client = $ENV{CEPH_CLIENT} || 'admin';

my $huge_file = "$Bin/test_huge_file";
if (-e $huge_file && -s $huge_file < 90 * 1024 * 1024) {
    warn "$huge_file was truncated, removing";
    unlink $huge_file;
}
if (!-e $huge_file) {
    diag "creating $huge_file";
    system "dd if=/dev/zero of=$huge_file count=125M iflag=count_bytes"
}

my %files;
{
    open my $HUGE, "$Bin/test_huge_file" or die "Cannot open $Bin/test_huge_file: $!";
    binmode $HUGE;
    undef $/;
    $files{test_huge} = $HUGE;
}

my $pool_created_p = system "ceph osd pool create $pool 1"
    unless $ENV{CEPH_POOL};
SKIP: {
    skip "Can't create $pool pool", 13 if $pool_created_p;

    my ($cluster, $io, $striper, $list, @stat);
    ok( $cluster = Ceph::Rados->new($client), "Create cluster handle" );
    ok( $cluster->set_config_file, "Read config file" );
    ok( $cluster->set_config_option(keyring => "/etc/ceph/ceph.client.$client.keyring"),
        "Set config option 'keyring'" );
    ok( $cluster->connect, "Connect to cluster" );
    ok( $io = $cluster->io($pool), "Open rados pool" );
    ok( $striper = Ceph::Rados::Striper->new($io), "Create striper" );

    while (my ($filename, $handle) = each %files) {
        ok( $striper->write($filename, $handle), "Write $filename object" );
        my $length = -s $handle;
        ok( my $stored_data = $striper->read($filename, $length),
            "Read back $filename object" );
        is( length($stored_data), $length,
            "Read $length bytes from $filename object" );
        # XXX removed until we have direct handle access
        #unless (
        #    ok( $stored_data eq <$handle>, "Get back $filename\'s content ok" )
        #) {
        #    my $rej_file = "$filename.rej";
        #    diag "Writing saved content to $rej_file";
        #    open my $REJ, ">$rej_file" or die "Cannot open $rej_file: $!";
        #    print $REJ $stored_data;
        #    close $REJ;
        #};
        ok( @stat = $striper->stat($filename), "Can stat uploaded file" );
        ok( $striper->remove($filename), "Remove $filename object" );
    }

    lives_ok { undef $list } "Closed list context";
    lives_ok { undef $io } "Closed rados pool";
    lives_ok { undef $cluster } "Disconnected from cluster";

    system "ceph osd pool delete $pool $pool --yes-i-really-really-mean-it"
        unless $ENV{CEPH_POOL};
}