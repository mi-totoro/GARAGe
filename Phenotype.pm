package Table::Phenotype;

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

has tablename	=> 'Phenotype';
has id_field	=> 'phenotypeid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub omims {
	my $class = shift;
	
	my $sql_cmd = "SELECT OMIMid from MIMtoPhenotype where phenotypeId = '".$class->get_id."';";
	my $sth = $class->{DB}->execute($sql_cmd);
	my @result;
	while (my $row = $sth->fetchrow_arrayref) {
		push @result, Table::OMIM->fetch($class->{DB}, $$row[0]);
		}
	return @result;
	}
































1;
