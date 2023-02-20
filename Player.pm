package Table::Player;

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

has tablename	=> 'Player';
has id_field	=> 'playername';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub playerTools {
	my $class = shift;
	
	my $target_package = "Table::PlayerTool";
	my @tools;
	my $TP_test = $target_package->new;
	my $sql_cmd = "SELECT ".$TP_test->id_field." FROM ".$TP_test->tablename." WHERE ".$class->id_field." = '".$class->get_id."';";
	my $sth = $class->{DB}->execute($sql_cmd);
	while (my $row = $sth->fetchrow_arrayref) {
		my $tool = $target_package->fetch($class->{DB}, $$row[0]);
		push @tools, $tool;
		}
	return @tools;
	}

sub playerInterpretationTableKey { # получить KEY интерпретаторской гугл таблицы, если она есть
	my $class = shift;
	}

sub GSHEET_I {
	my $class = shift;

	my $sth = "select playerToolFieldValue from Player INNER JOIN PlayerTool ON PlayerTool.playerName = Player.playerName INNER JOIN PlayerToolField ON PlayerToolField.playerToolID = PlayerTool.playerToolID where playerToolFieldName = 'GSHEET_key' and Player.playerName = '".$class->get_id."';";
	$sth = $class->{DB}->execute_select_single($sth);
	return $sth;
	}




































1;
