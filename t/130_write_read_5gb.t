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

my $giant_file = "$Bin/test_giant_file";
if (-e $giant_file && -s $giant_file < 5 * 1024 * 1024 * 1024) {
    warn "$giant_file was truncated, removing";
    unlink $giant_file;
}
if (!-e $giant_file) {
    diag "creating $giant_file";
    system "dd if=/dev/zero of=$giant_file count=5G iflag=count_bytes"
}

my %files;
{
    open my $GIANT, "$Bin/test_giant_file" or die "Cannot open $Bin/test_giant_file: $!";
    binmode $GIANT;
    undef $/;
    # add process ID so we don't get guaranteed clashes from repeated runs
    $files{"test_giant.$$"} = $GIANT;
}

my $pool_created_p = system "ceph osd pool create $pool 1"
    unless $ENV{CEPH_POOL};
SKIP: {
    skip "Can't create $pool pool", 11 if $pool_created_p;

    my ($cluster, $io, $striper, $list, @stat);
    ok( $cluster = Ceph::Rados->new($client), "Create cluster handle" );
    ok( $cluster->set_config_file, "Read config file" );
    ok( $cluster->set_config_option(keyring => "/etc/ceph/ceph.client.$client.keyring"),
        "Set config option 'keyring'" );
    ok( $cluster->connect, "Connect to cluster" );
    ok( $io = $cluster->io($pool), "Open rados pool" );
    ok( $striper = Ceph::Rados::Striper->new($io), "Create striper" );

    while (my ($filename, $handle) = each %files) {
        ok( $striper->write($filename, $handle, 1), "Write $filename object" );
        my ($size, $mtime);
        ok( ($size, $mtime) = $striper->stat($filename), "Stat $filename object" );
        my $length = -s $handle;
        is( $size, $length, "stat size equals handle length" );
        ok($mtime, "mtime $mtime is sane");
        my $out_fn = "/tmp/$$.test.out";
        open my $out_fh, ">$out_fn"
            or die "Could not open output filehandle '$out_fn': $!";
        ok( $striper->read_handle($filename, $out_fh, 0, 0, 1),
            "Read back $filename object" );
        close $out_fh;
        is( -s $out_fn, $length, "Files have equal size" )
            or diag "check $out_fn";
        ok( @stat = $striper->stat($filename), "Can stat uploaded file" );
        ok( $striper->remove($filename), "Remove $filename object" );
    }

    lives_ok { undef $list } "Closed list context";
    lives_ok { undef $io } "Closed rados pool";
    lives_ok { undef $cluster } "Disconnected from cluster";

    system "ceph osd pool delete $pool $pool --yes-i-really-really-mean-it"
        unless $ENV{CEPH_POOL};
}
