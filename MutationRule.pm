package Table::MutationRule;

use strict;
use warnings;
use Dir::Self;
use parent 'Table';
use lib __DIR__;

use Aoddb;
use Atlas;
use File::Basename;
use Data::Dumper;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Mojo::Base -base;

has tablename	=> 'MutationRule';
has id_field	=> 'mutationruleid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub Mutation {
	my $class = shift;
	return $class->{DB}->Mutation($class->info->{mutationid});
	}

sub name {
	my $class = shift;

	my $Mutation = $class->{DB}->Mutation($class->info->{mutationid});
	my $zyg = lc($class->info->{zygosity});
	return undef unless defined $Mutation;
	return undef unless defined $zyg;
	my $name = $Mutation->name;
	$name = lc("$name:$zyg");
	return $name;
	}

sub isPositive {
	my $class	= shift;
	my $Parent	= shift;
	if ((ref $Parent) =~ /Analysis/) {
		return $class->isPositive_Analysis($Parent);
		}
	if ((ref $Parent) =~ /Case/) {
		return $class->isPositive_Case($Parent);
		}
	}

sub isPositive_Case {
	my $class	= shift;
	my $Case	= shift;
	my $ResultStructure = shift;
	
	unless (defined($ResultStructure)) {
		foreach my $Barcode ($Case->barcodes) {
			my $Analysis = $Barcode->major_AN;
			next unless defined $Analysis;
			$ResultStructure->{MutationResult}->{$Analysis->get_id} = [$Analysis->mutationResults];
			}
		}

	if (lc($class->info->{zygosity}) =~ /wt/) {
		my $result = 1; # Изначально результат положительный - мутации нет
		foreach my $Barcode ($Case->barcodes) {
			my $Analysis = $Barcode->major_AN;
			next unless defined $Analysis;
			if ($class->isPositive_Analysis($Analysis, $ResultStructure) eq '0') {
				$result = 0;
				}
			}
		return $result;
		} else {
		my $result = 0;
		foreach my $Barcode ($Case->barcodes) {
			my $Analysis = $Barcode->major_AN;
			next unless defined $Analysis;
			if ($class->isPositive_Analysis($Analysis, $ResultStructure) eq '1') {
				$result = 1;
				}
			}
		return $result;
		}
	}

sub isPositive_Analysis {
	my $class	= shift;
	my $Analysis	= shift;
	my $ResultStructure = shift;
	my $mutationResults;
	if ((defined($ResultStructure))and(defined($ResultStructure->{MutationResult}->{$Analysis->get_id}))) {
		$mutationResults = $ResultStructure->{MutationResult}->{$Analysis->get_id};
		} else {
		$mutationResults = $Analysis->mutationResults;
		}
	my $found = 0;
	if (lc($class->info->{zygosity}) =~ /wt/) {
		my $found = 0;
		foreach my $MutationResult (@{$mutationResults}) {
			next if $MutationResult->info->{mutationid} ne $class->info->{mutationid};
			my $zygosity;
			if (defined($MutationResult->info->{zygosityvalidated})) {
				$zygosity = $MutationResult->info->{zygosityvalidated};
				} elsif (defined($MutationResult->info->{zygositycurated})) {
				$zygosity = $MutationResult->info->{zygositycurated};
				} elsif (defined($MutationResult->info->{zygosityautomatic})) {
				$zygosity = $MutationResult->info->{zygosityautomatic};
				}
			next unless defined $zygosity;
			if (not(lc($zygosity) =~ /wt/)) {
				$found = 1;
				last;
				}
			}
		if ($found eq 0) {return 1} else {return 0}
		} else {
		my $found = 0;
		foreach my $MutationResult ($mutationResults) {
			next if $MutationResult->info->{mutationid} ne $class->info->{mutationid};
			my $zygosity;
			if (defined($MutationResult->info->{zygosityvalidated})) {
				$zygosity = $MutationResult->info->{zygosityvalidated};
				} elsif (defined($MutationResult->info->{zygositycurated})) {
				$zygosity = $MutationResult->info->{zygositycurated};
				} elsif (defined($MutationResult->info->{zygosityautomatic})) {
				$zygosity = $MutationResult->info->{zygosityautomatic};
				}
			next unless defined $zygosity;
			if ((lc($zygosity) eq lc($class->info->{zygosity}))or
				((lc($zygosity) eq 'variant_nos')and(lc($class->info->{zygosity}) eq 'somatic'))or
				((lc($zygosity) eq 'variant_nos')and(lc($class->info->{zygosity}) eq 'germline_het'))or
				((lc($zygosity) eq 'variant_nos')and(lc($class->info->{zygosity}) eq 'germline_hom'))or
				((lc($zygosity) eq 'variant_nos')and(lc($class->info->{zygosity}) eq 'germline_nos'))) {
				$found = 1;
				last;
				}
			}
		return $found;
		}
	}

sub fetch {
	my $class = shift;
	my $DB = shift;
	my $id = shift;
	
	my $self = $class->new;
	$self->connect($DB);
	if ($id =~ /^(\d+)$/) {
		$self->fetch_info($id);
		eval {$self->get_id};
		if ($@) {
			print STDERR "$@" if $verbose;
			return undef;
			} else {
			if (defined $self->get_id) {
				return $self;
				} else {
				print STDERR "Could not fetch data from table",$class->tablename,"\n" if $verbose;
				return undef;
				}
			}
		} elsif ($id =~ /^(\S+):(\d+)([AGCTNagctn]+)>([AGCTNagctn]+):(\S+)$/) {
		my $chr = $1;
		my $pos = $2;
		my $ref = $3;
		my $alt = $4;
		my $zyg = $5;
		my $sql_cmd = "select mutationruleid from MutationRule INNER JOIN Mutation ON Mutation.mutationId = MutationRule.mutationId where Mutation.mutationChr = '$chr' and Mutation.mutationGenomicPos = '$pos' and Mutation.mutationRef = '$ref' and Mutation.mutationAlt = '$alt' and MutationRule.zygosity = '$zyg';";
		my $sth = $DB->execute($sql_cmd);
		my $row = $sth->fetchrow_arrayref;
		return undef unless defined $$row[0];
		return $class->fetch($DB, $$row[0]);
		} else {
		return undef;
		}
	return undef;
	}

sub forceFetch {
	my $class	= shift;
	my $DB		= shift;
	my $name	= shift;
	my $self = $class->fetch($DB, $name);
	if (defined($self)) {
		return $self;
		} else {
		if ($name =~ /^(\S+):(\d+)([AGCTNagctn]+)>([AGCTNagctn]+):(\S+)$/) {
			my $chr = $1;
			my $pos = $2;
			my $ref = $3;
			my $alt = $4;
			my $zyg = $5;
			my $Mutation = $DB->Mutation("$chr:$pos$ref>$alt");
			return undef unless defined $Mutation;
			return $Mutation->fetchRule($zyg);
			} else {
			return undef;
			}
		}
	}





























1;
