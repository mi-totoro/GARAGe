package Table::LibraryQC;

use strict;
use warnings;
use Dir::Self;
use parent 'Table';
use lib __DIR__;

use Aoddb;
use Atlas;
use File::Basename;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Mojo::Base -base;
use Data::Dumper;

has tablename	=> 'LibraryQC';
has id_field	=> 'barcodename';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub status {
	my $class = shift;
	
	my $barcode_name = $class->get_id;
	return undef unless defined $barcode_name;
	my $sql_cmd = "SELECT LibraryQC.result from LibraryQC where barcodeName = '$barcode_name';";
	my $sth = $class->{DB}->execute($sql_cmd);
	while (my $row = $sth->fetchrow_arrayref) {
		return $$row[0];
		}
	return undef;
	}

sub change_status {
	my $class = shift;
	my $status = shift; # FAIL/PASS/NULL
	$status = uc($status);
	
	if (($status eq 'FAIL')or($status eq 'PASS')) {
		my $barcode_name = $class->get_id;
		my $sql_cmd;
		if (defined $class->status) {
			return 0 if $status eq $class->status;
			$sql_cmd = "UPDATE `LibraryQC` SET `result` = '$status', analysisVersion = 'Claudia' where barcodeName = '$barcode_name';";
			} else {
			$sql_cmd = "INSERT INTO `LibraryQC` (`barcodeName`, `result`, `analysisVersion`) VALUES ('$barcode_name', '$status', 'Claudia');";
			}
		my $sth = $class->{DB}->execute($sql_cmd);
		} elsif ($status eq 'NULL') {
			my $barcode_name = $class->get_id;
			if (defined($class->status)) {
				my $sql_cmd = "DELETE FROM `LibraryQC` where barcodeName = '$barcode_name';";
				my $sth = $class->{DB}->execute($sql_cmd);
				}
			} else {die "Unknown library QC status"}
	return 0;
	}

sub PASS {
	my $class = shift;
	$class->change_status('PASS');
	}

sub FAIL {
	my $class = shift;
	$class->change_status('FAIL');
	}




























1;
