package Table::PlayerTool;

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

has tablename	=> 'PlayerTool';
has id_field	=> 'playertoolid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub playerToolFields {
        my $class = shift;

        my $target_package = "Table::PlayerToolField";
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

sub PlayerToolField {
	my $class = shift;
	my $field_name = shift;
	
	my @fields = $class->playerToolFields;
	return undef if (scalar @fields eq 0);
	@fields = grep {$_->info->{playertoolfieldname} eq $field_name} @fields;
	return undef if (scalar @fields eq 0);
	die "Multiple fields found" if (scalar @fields > 1);
	return $fields[0];
	}

sub Player {
	my $class = shift;
	return $class->{DB}->Player($class->info->{playername});
	}




































1;
