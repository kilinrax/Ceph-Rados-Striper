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

my $small_file = "$Bin/test_small_file";
if (!-e $small_file) {
    diag "creating $small_file";
    system "echo 'quux' >$small_file"
}

my %files;
{
    open my $SMALL, "$Bin/test_small_file" or die "Cannot open $Bin/test_small_file: $!";
    binmode $SMALL;
    undef $/;
    $files{test_small} = $SMALL;
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
        ok( $striper->write($filename, $handle), "Write $filename object" );
        my $length = -s $handle;
        my $out_fn = "/tmp/$$.test.out";
        open my $out_fh, ">$out_fn"
            or die "Could not open output filehandle '$out_fn': $!";
        ok( $striper->read_handle($filename, $out_fh),
            "Read back $filename object" );
        close $out_fh;
        is( -s $out_fn, $length, "Files have equal size" );
        #ok( $stored_data = $striper->read_to_filehandle($filename, length),
        #    "Read back $filename object" );
        #is( length($stored_data), $length,
        #    "Read $length bytes from $filename object" );
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
