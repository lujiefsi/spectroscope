#! /usr/bin/perl -w

#
# Copyright (c) 2013, Carnegie Mellon University.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of the University nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
# HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
# OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
# WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

# $cmuPDL: StructuredGraph.pm,v 1.8 2010/04/13 05:05:38 ww2 Exp $

## 
# This module can be used to build a structured request-flow graph.  
# The request-flow graph can be build in two ways.
#
# 1)The graph can be built based on its DOT representation by calling
# build_graph_structure_from_dot().  Once this function is called, the graph has
# been finalized.  It cannot be modified by using any of the 'create_node' or
# 'create_root' fns.  Only the 'get' accessor functions cna be used to
# retrievethe various elements of the graph.
#
# 2)The graph can be built iteratively using the create_root() and create_node()
# fns.  The caller should use these fns to build the complete graph, then when
# done, call finalize_graph_structure().  After finalize_graph_structure() is
# called, the accessor functions can be used to access the individual elements
# of the graph.
#
# This object also contains a method for printing a structured graph to DOT format
##
package StructuredGraph;

use strict;
use warnings;
use Test::Harness::Assert;

use ParseDot::DotHelper qw[parse_nodes_from_string];
use Data::Dumper;

require Exporter;
our @EXPORT_OK = qw(build_graph_structure);

#### Global Constants #########

# Import value of DEBUG if defined
no define DEBUG =>;


#### Private functions ########

##
# Sorts the children array of each node in the graph_structure
# hash by the name of the node.  This is done to prevent false differences
# between two different graphs caused to due to ordering differences in the
# children of a node.
#
# @param graph_structure_hash: A pointer to a hash containing the nodes
# of a request-flow graph.
##
sub sort_graph_structure_children {
    
    assert(scalar(@_) == 1);

    my $graph_structure_hash = shift;

    foreach my $key (keys %$graph_structure_hash) {
        my $node = $graph_structure_hash->{$key};
        my @children = @{$node->{CHILDREN}};
        
        my @sorted_children = sort {$graph_structure_hash->{$a}->{NAME} cmp 
                                        $graph_structure_hash->{$b}->{NAME}} @children;
        $node->{CHILDREN} = \@sorted_children;

        my @parents = @{$node->{PARENTS}};
        my @sorted_parents = sort {$graph_structure_hash->{$a}->{NAME} cmp
                                       $graph_structure_hash->{$b}->{NAME}} @parents;
        $node->{PARENTS} = \@sorted_parents;
    }

};


##
# Builds a tree representation of a DOT graph passed in as a string and finalizes
# the graph.  This means that only the "get" accessor methods can be used to retrieve
# elements of the tree after this function is called.
# 
# @note: This function expects the input DOT representation to have been
# printed using a depth-first traversal.  Specifically, the source node
# of the first edge printed MUST be the root.
#
# @todo: This method should not be visible to the external caller.  The new()
# routine below should be the only function that can call this routine.
# Unfortunately MatchGraphs.pm and DecisionTree.pm use this function currently;
# they need to be modified to use the object interface.
#
# @param graph: A string representation of the DOT graph
#
# @return: A hash: 
#    { ROOT => reference to hash containing root node info
#      NODE_HASH => reference to hash of nodes keyed by node id
#
# Each node is a hash that is comprised of: 
#   { NAME => string,
#     CHILDREN => ref to array of IDs of children
#     PARENTS => ref to array of IDs of parents
#     ID => This Node's ID
##
sub build_graph_structure {
    
    assert(scalar(@_) == 1);

    my ($graph) = @_;

    my %graph_node_hash;
    # @note DO NOT include semantic labels when parsing nodes from the string
    # in this case
    DotHelper::parse_nodes_from_string($graph, 0, \%graph_node_hash);
    
    my %graph_structure_hash;
    my %edge_latencies_hash;
    my $first_line = 1;
    my $root_ptr;

    my @graph_array = split(/\n/, $graph);

    # Build up the graph structure hash by iterating through
    # the edges of the graph structure
    foreach(@graph_array) {
        my $line = $_;
        
        if ($line =~m/(\d+)\.(\d+) \-> (\d+)\.(\d+) \[label="R: ([0-9\.]+) us"\]/) {
            my $src_node_id = "$1.$2";
            my $dest_node_id = "$3.$4";

            assert(!defined $edge_latencies_hash{$src_node_id}{$dest_node_id});
            $edge_latencies_hash{$src_node_id}{$dest_node_id} = $5;
            
            my $src_node_name = $graph_node_hash{$src_node_id};
            my $dest_node_name = $graph_node_hash{$dest_node_id};
            
            if(!defined $graph_structure_hash{$dest_node_id}) {
                my %dest_node = (NAME => $dest_node_name,
                                 CHILDREN => [],
                                 PARENTS  => [],
                                 ID => $dest_node_id);
                $graph_structure_hash{$dest_node_id} = \%dest_node;
            }
            push(@{$graph_structure_hash{$dest_node_id}->{PARENTS}}, $src_node_id);

            if (!defined $graph_structure_hash{$src_node_id}) {
                my %src_node =  ( NAME => $src_node_name,
                                  CHILDREN => [],
                                  PARENTS => [],
                                  ID => $src_node_id);
                $graph_structure_hash{$src_node_id} = \%src_node;
            }
            push(@{$graph_structure_hash{$src_node_id}->{CHILDREN}}, $dest_node_id);

            # If this is the first edge parsed in the graph, then this is 
            # also the root of the graph.  
            # @bug: Probably should get red of this!}
            if($first_line == 1) {
                $root_ptr = $graph_structure_hash{$src_node_id},
                $first_line = 0;
            }
        }
    }
    
    # Finally, sort the children array of each node in the graph structure
    # alphabetically
    sort_graph_structure_children(\%graph_structure_hash);

    return { ROOT => $root_ptr, NODE_HASH => \%graph_structure_hash,
             EDGE_LATENCIES_HASH => \%edge_latencies_hash};
}


#### Private functions ############

##
# Creates a new node and returns it
#
# @param name: The name to assign the node
# @return: A pointer to a hash that contains the node
##
my $_create_node = sub {

    assert(scalar(@_) == 2);
    my ($self, $name) = @_;
    
    my @children_array;
    my @parents_array;
    my $id = $self->{CURRENT_NODE_ID}++;
    my %node = ( NAME => $name,
                 CHILDREN => \@children_array,
                 PARENTS => \@parents_array,
                 ID => "$self->{PREPEND_ID}" . "$id" );

    return \%node;
};


##
# Helper function for print_dot().  Prints the nodes
# of this graph in DOT format to the fd specified
#
# @param self: The object container
# @param fd: The file descriptor
##
my $_print_dot_nodes = sub {
    assert(scalar(@_) == 2);
    my ($self, $fd) = @_;

    my $hash = $self->{GRAPH_STRUCTURE_HASH};

    foreach my $node_id (keys %{$hash}) {
        my $name = $hash->{$node_id}->{NAME};
        
        printf $fd "%s.%s [label=\"%s\\n\"]\n", $node_id, $node_id, $name;
    }
};


##
# Helper function for print_dot().  Print edges
# of this graph in DOT format to the fd specified
#
# @param self: The object container
# @param src_node_id: The source node of the edge
# @param dest_node_id: The dest node of the edge
# @param traversed: Whether or not the path rooted
#  at dest_node_id has already been traversed
# @param fd: The file descriptor
##
my $_print_dot_edges;
$_print_dot_edges = sub {
    assert(scalar(@_) == 5);
    my ($self, $src_node_id, $dest_node_id, $traversed, $fd) = @_;

    my $graph = $self->{GRAPH_STRUCTURE_HASH};
    my $edge_latencies_hash = $self->{EDGE_LATENCIES_HASH};

    if (!defined $src_node_id) {
        my $dest_node = $graph->{$dest_node_id};
        my $children_ids = $dest_node->{CHILDREN};
        
        foreach (@{$children_ids}) {
            $self->$_print_dot_edges($dest_node_id, $_, $traversed, $fd);
        }
        return;
    }

    # Print the edge latency
    my $edge_latency = $edge_latencies_hash->{$src_node_id}{$dest_node_id};
    assert(defined $edge_latency);

    printf $fd "%s.%s -> %s.%s [label=\"R: %f us\"]\n", 
    $src_node_id, $src_node_id, $dest_node_id, $dest_node_id, $edge_latency;

    # If the path rooted at dest_id has already been traversed , simply return
    if (defined $traversed->{$dest_node_id}) {
        return;
    }

    # Call print_dot_edges recursively on children
    my $dest_node = $graph->{$dest_node_id};
    my $children_ids = $dest_node->{CHILDREN};

    foreach (@{$children_ids}) {
        $self->$_print_dot_edges($dest_node_id, $_, $traversed, $fd);
    }

    $traversed->{$dest_node_id} = 1;
};


##### Public Object functions ##############################

##
# Creates a new structured graph object
#
# @param proto
# @param req_str: (OPTIONAL) A request in DOT format.  If specified
#  a structured graph will be created based on this string and finalized
#  immediately.[
# @param id: A value that will be prepended to the IDs of every node in
#  this graph. 
##
sub new {
    
    assert(scalar(@_) == 2 || scalar(@_) == 3);
    
    my ($proto, $req_str, $id);
    if (scalar(@_) == 3) {
        ($proto, $req_str, $id) = @_;
    } else {
        ($proto, $id) = @_;
    }

    my $class = ref($proto) || $proto;
    my $self = {};

    if(defined $req_str) {
        my $container = build_graph_structure($req_str);
        $self->{GRAPH_STRUCTURE_HASH} = $container->{NODE_HASH};
        $self->{ROOT} = $container->{ROOT};
        $self->{EDGE_LATENCIES_HASH} = $container->{EDGE_LATENCIES_HASH};
        $self->{CURRENT_NODE_ID} = 1;
        $self->{FINALIZED} = 1;
        $self->{PREPEND_ID} = $id;

    } else {
        my %graph_structure_hash;
        my %edge_latencies_hash;
        $self->{GRAPH_STRUCTURE_HASH} = \%graph_structure_hash;
        $self->{EDGE_LATENCIES_HASH} = \%edge_latencies_hash;
        $self->{ROOT} = undef;
        $self->{CURRENT_NODE_ID} = 1;
        $self->{PREPEND_ID} = $id;
        $self->{FINALIZED} = 0;
    }

    bless($self, $class);
}


##
# Interface to adding a root node
#
# @param self: The 
# @param name: The name of the root node
#
# @return: An id for the root node
##
sub add_root {
    assert(scalar(@_) == 2);
    my ($self, $name) = @_;

    my $blah = $self->{ROOT};
    assert(!defined $self->{ROOT});
    assert($self->{FINALIZED} == 0);

    my $graph_structure_hash = $self->{GRAPH_STRUCTURE_HASH};

    my $node = $self->$_create_node($name);

    $graph_structure_hash->{$node->{ID}} = $node;
    $self->{ROOT} = $node;
    assert(defined $node);
    $self->{FINALIZED} = 0;

    return $node->{ID};
};


##
# Interface for adding a child to a given parent
#
# @param self: The object container 
# @param parent_node_id: ID of the parent node
# @param child_node_name: ID of the child node
# @param the edge latency for the parent/child
##
sub add_child {
    assert(scalar(@_) == 4);
    my ($self, $parent_node_id, $child_node_name, $edge_latency) = @_;

    assert($self->{FINALIZED} == 0);
    
    my $graph_structure_hash = $self->{GRAPH_STRUCTURE_HASH};
    my $edge_latencies_hash = $self->{EDGE_LATENCIES_HASH};

    my $child_node = $self->$_create_node($child_node_name);    
    my $parent_node = $graph_structure_hash->{$parent_node_id};
    
    push(@{$parent_node->{CHILDREN}}, $child_node->{ID});
    push(@{$child_node->{PARENTS}}, $parent_node_id);
    $graph_structure_hash->{$child_node->{ID}} = $child_node;

    assert(!defined $edge_latencies_hash->{$parent_node_id}{$child_node->{ID}});
    $edge_latencies_hash->{$parent_node_id}{$child_node->{ID}} = $edge_latency;

    return $child_node->{ID};
}

##
# Interface for adding a existing child to a given parent
#
# @param self: The object container 
# @param parent_node_id: ID of the parent node
# @param child_node_id: ID of the child node
# @param the edge latency for the parent/child
##
sub add_existing_child {
    assert(scalar(@_) == 4);
    my ($self, $parent_node_id, $child_node_id, $edge_latency) = @_;
    
    assert($self->{FINALIZED} == 0);
    
    my $graph_structure_hash = $self->{GRAPH_STRUCTURE_HASH};
    my $edge_latencies_hash = $self->{EDGE_LATENCIES_HASH};
    
    my $parent_node = $graph_structure_hash->{$parent_node_id};
    my $child_node = $graph_structure_hash->{$child_node_id};

    push(@{$parent_node->{CHILDREN}}, $child_node_id);
    push(@{$child_node->{PARENTS}}, $parent_node_id);
    $edge_latencies_hash->{$parent_node_id}{$child_node_id} = $edge_latency;
}

##
# Finalizes the graph structure by ordering children nodes at
# each level in alphabetical order.  This function should be called
# after creating the complete graph and before retrieving individual
# nodes.
#
# @param: self: The object container
##
sub finalize_graph_structure {
    
    assert(scalar(@_) == 1);
    my ($self) = @_;
    
    sort_graph_structure_children($self->{GRAPH_STRUCTURE_HASH});
    $self->{FINALIZED} = 1;
}


##
# Returns the root node's id
#
# @param self: The object container
# 
# @return: The ID of the rootnode
##
sub get_root_node_id {
    assert(scalar(@_) == 1);
    my ($self) = @_;
    
    assert(defined $self->{ROOT});
    
    return $self->{ROOT}->{ID};
}


##
# Interface for getting the name of a node given it's ID
#
# @param node_id: The ID of the node
#
# @return: A string indicating the node ID
##
sub get_node_name {
    assert(scalar(@_) == 2);
    my ($self, $node_id) = @_;
    
    my $graph_structure_hash = $self->{GRAPH_STRUCTURE_HASH};
    
    assert(defined $graph_structure_hash->{$node_id});
    
    return $graph_structure_hash->{$node_id}->{NAME};
}

##
# Sub get edge latency
#
# @param parent_node_id: The node id of the parent
# @param child_node_id: The node id of the child
#
# @return the edge latency
##
sub get_edge_latency  {
    assert(scalar(@_) == 3);
    my ($self, $parent_id, $child_id) = @_;

    my $edge_latencies_hash = $self->{EDGE_LATENCIES_HASH};
 
   return $edge_latencies_hash->{$parent_id}{$child_id};
}


##
# Interface for getting the children IDs of a node
#
# @param self: The object container
# @param node_id: The ID of the node for which to return children
# 
# @return a pointer to an array of node ids
##
sub get_children_ids {
    assert(scalar(@_) == 2);
    my ($self, $node_id) = @_;
    
    my $graph_structure_hash = $self->{GRAPH_STRUCTURE_HASH};
    
    assert(defined $graph_structure_hash->{$node_id});
    
    my @children_copy = @{$graph_structure_hash->{$node_id}->{CHILDREN}};
    
    return \@children_copy;
}


##
# Interface for getting the parent IDs of a node
#
# @param self: The object cotnainer
# @param node_id: The ID of the node for which to retunr children
#
# @paren a pointer to an array of node ids
sub get_parent_ids {
    assert(scalar(@_) == 2);
    my ($self, $node_id) = @_;
    
    my $graph_structure_hash = $self->{GRAPH_STRUCTURE_HASH};
    
    assert(defined $graph_structure_hash->{$node_id});
    
    my @parents_copy = @{$graph_structure_hash->{$node_id}->{PARENTS}};
    
    return \@parents_copy;
}


##
# Prints out a depth-first DOT representation of the graph
#
# @param fd: The file to which to print the grpah
##
sub print_dot {

    assert(scalar(@_) == 2);
    my ($self, $fd) = @_;

    printf $fd "Digraph $self->{PREPEND_ID} {\n";

    $self->$_print_dot_nodes($fd);

    my %traversed;
    $self->$_print_dot_edges(undef, $self->{ROOT}->{ID}, \%traversed, $fd);

    printf $fd "}\n";
}
