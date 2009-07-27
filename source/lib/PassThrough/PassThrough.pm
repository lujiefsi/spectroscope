#! /usr/bin/perl -w

# $cmuPDL: PassThrough.pm,v 1.2 2009/04/26 23:48:44 source Exp $
##
# This perl modules implements a "ClusteringPassThrough"
# that is, it generates as many clusters as input
# datapoints.  This code generates the following output file:
#
# clusters.dat: A file, where each row represents a cluster.  
# The first column represents the offset into the input 
# vector file of the cluster representative the other other 
# columns indicate offsets of the datapoints assigned to the cluster.
#
# The code takes as input a data vector, where each row is a datapoint
# and each column a dimension.  The first two columns of each row
# are: <number of reqs in s0, number of reqs in s1>
##

package PassThrough;

use strict;
use Getopt::Long;
use Test::Harness::Assert;


#### Private functions #######################

##
# Removes existing files created by this perl module,
# if they already exist in the output directory
#
# @param self: The object container
##
my $_remove_existing_files = sub {
    my $self = shift;

    if(-e $self->{INPUT_VECTOR_FILE}) {
        print("Deleting old $self->{INPUT_VECTOR_FILE}\n");
        system("rm -f $self->{INPUT_VECTOR_FILE}") == 0
            or die("Could not delete old $self->{INPUT_VECTOR_FILE}\n");
    }
};


#### API functions ###############################

sub new {
    assert(scalar(@_) == 3);
    my ($proto, $input_dir, $output_dir) = @_;

    my $class = ref($proto) || $proto;

    my $self = {};

    $self->{INPUT_VECTOR_FILE} = "$input_dir/input_vector.dat";
    $self->{DISTANCE_MATRIX_FILE} = "$input_dir/distance_matrix.dat";
    $self->{CLUSTER_FILE} = "$output_dir/clusters.dat";

    bless($self, $class);
    return $self;
}


##
# Returns 1 if the output file generated by this class
# already exists in the output directory
#
# @param self: The object-container
##
sub do_output_files_exist {
    my $self = shift;

    if ( -e($self->{CLUSTER_FILE})) {
        return 1;
    }

    return 0;
}


##
# Iterates through the input vector and 
# spits out the line number to the clusters.dat file.
#
# @param self: The object container
##
sub cluster {
    my $self = shift;
    
    open(my $input_vector_fh, "<$self->{INPUT_VECTOR_FILE}") 
        or die("Could not open $self->{INPUT_VECTOR_FILE}");
    open(my $output_fh, ">$self->{CLUSTER_FILE}")
        or die("Could not open $self->{CLUSTER_FILE}");
    
    my $offset = 1;
    while (<$input_vector_fh>) {
        print $output_fh "$offset\n";
        $offset++;
    }

    close($input_vector_fh);
    close($output_fh);
}


1;
