package File;

use strict;
use warnings;
use Dir::Self;
use lib __DIR__;

use Aoddb;
use Atlas;
use File::Basename;
use Data::Dumper;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Mojo::Base -base;

our @ISA = qw(Exporter);
our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub new {
	my $class = shift;
	my $path  = shift;
	if (open (my $file, "<$path")) {
		close $file;
		} else {
		return undef;
		}
	my $self  = {};
	$self->{info} = {};
	$self->{info}->{path} = $path;
	return (bless $self, $class);
	}

sub info {
	my $class = shift;
	return $class->{info};
	}

sub path { # RETURN FULL PATH TO FILE
	my $class = shift;
	return $class->info->{path};
	}

sub base_name { # RETURN FULL PATH WITHOUT EXTENSION
	my $class = shift;
	
	if ($class->path =~ /(\S+)\.([^.]+)$/) {
		return $1;
		}
	return undef;
	}

sub name { #RETURN ONLY FILE NAME (WITH EXTENSION)
	my $class = shift;
	
	if ($class->path =~ /([^\/]+)$/) {
		return $1;
		}
	return undef;
	}









1;
