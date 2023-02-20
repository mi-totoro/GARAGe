package Table::Pathology;

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

has tablename	=> 'Pathology';
has id_field	=> 'pathologycode';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub find_distance_up {
	# Найти расстояние до указанного заболевания по направлению к корню
	my $class  = shift;
	my $target = shift; # Заболевание до которого ведется поиск по дереву
	my @path = split/\./, $class->info->{pathologypath};
	for (my $i = 0; $i < scalar @path; $i++) {
		if (lc($path[$i]) eq lc($target)) {
			return (scalar(@path)-1-$i);
			}
		}
	return (-1);
	}

sub find_distance_down {
	# Найти расстояние до указанного заболевания по направлению от корня
	my $class  = shift;
	my $target = shift; # Заболевание до которого ведется поиск по дереву
	my @path = split/\./, $class->{DB}->Pathology($target)->info->{"pathologypath"};
	for (my $i = 0; $i < scalar @path; $i++) {
		if (lc($path[$i]) eq lc($class->info->{pathologycode})) {
			return (scalar(@path)-1-$i);
			}
		}
	return (-1);
	}

























1;
