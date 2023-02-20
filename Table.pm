package Table;

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

has tablename	=> 'default';
has id_field 	=> 'default';

our @ISA = qw(Exporter);
our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub new {
	my $class = shift;
	my $self = {};
	$self->{info} = {};
	$self->{meta} = {};
	return (bless $self, $class);
	}

sub connect {
	my $class = shift;
	my $db = shift;
	
	$class->{'DB'} = $db;
	}

sub load_info {
	my $class = shift;
	my $info  = shift;
	foreach my $key (keys %{$info}) {
		if (lc($key) eq 'casename') {
			$info->{caseid} = Atlas::grep_case_id($info->{$key}) if $class->is_field_exist("caseid");
			$info->{patientid} = Atlas::grep_patient_id($info->{$key}) if $class->is_field_exist("patientid");
			delete($info->{$key}) unless $class->is_field_exist($key);
			}
		if (lc($key) eq 'barcodename') {
			$info->{caseid} = Atlas::grep_case_id($info->{$key}) if $class->is_field_exist("caseid");
			$info->{patientid} = Atlas::grep_patient_id($info->{$key}) if $class->is_field_exist("patientid");
			$info->{barcodeid} = Atlas::grep_barcode_id($info->{$key}) if $class->is_field_exist("barcodeid");
			delete($info->{$key}) unless defined $class->is_field_generated($key);
			}
		if (lc($key) eq 'analysisname') {
			$info->{caseid} = Atlas::grep_case_id($info->{$key}) if $class->is_field_exist("caseid");
			$info->{patientid} = Atlas::grep_patient_id($info->{$key}) if $class->is_field_exist("patientid");
			$info->{barcodeid} = Atlas::grep_barcode_id($info->{$key}) if $class->is_field_exist("barcodeid");
			$info->{analysisid} = Atlas::grep_analysis_id($info->{$key}) if $class->is_field_exist("analysisid");
			delete($info->{$key}) unless defined $class->is_field_generated($key);
			}
		}
	my $result;
	my @cols = $class->get_field_dic;
	OUTER_LOAD_INFO: foreach my $key (keys %{$info}) {
		foreach my $arg (@cols) {
			my $dic = $arg; $dic = lc($dic);
			my $cur = $key; $cur = lc($cur);
			if ($cur =~ /info:(\S+)/) {
				$cur = $1;
				}
			next OUTER_LOAD_INFO if $class->is_field_generated($cur);
			if ($cur =~ /meta:(\S+)/) {
				$cur = $1;
				$class->{meta}->{$cur} = $info->{$key};
				next OUTER_LOAD_INFO;
				}
			if ($dic eq $cur) {
				$class->{info}->{$arg} = $info->{$key};
				next OUTER_LOAD_INFO;
				}
			}
		print STDERR "WARNING: field $key was not found in mysql database\n" if $verbose;
		}
	return 0;
	}

sub delete {
	my $class = shift;
	my $dbh = $class->{DB}->{mysql};
	
	my $id = $class->get_id;
	my $sql_cmd = "delete from `".$class->tablename."` where ".$class->id_field." = '$id';";
	my $sth = $class->{DB}->execute($sql_cmd);
	print STDERR "".$class->tablename." $id removed from database\n" if $verbose;
#	$class->folder_remove;
	return 0;
	}

sub assign_id {
	my $class = shift;
	my $id = shift;
	my $id_name = $class->id_field;
	$class->{info}->{$id_name} = $id;
	}

sub is_field_pk {
	my $class = shift;
	my $field = shift;
	return ($class->{DB}->is_table_field_pk($class->tablename, $field));
	}

sub is_field_ai {
	my $class = shift;
	my $field = shift;
	return ($class->{DB}->is_table_field_AI($class->tablename, $field));
	}

sub field_max_value {
	my $class = shift;
	my $field = shift;
	my $sth = "SELECT MAX($field) FROM `".$class->tablename."`";
	$sth = $class->{DB}->execute_select_single($sth);
	unless (defined($sth)) {
		return 0;
		}
	if (lc($sth) eq 'null') {
		return 0;
		}
	return $sth;
	}

sub field_next_value {
	my $class = shift;
	my $field = shift;
	return ($class->field_max_value($field) + 1);
	}

sub is_field_exist {
	my $class = shift;
	my $field = shift;
	my $dbh = $class->{DB}->{mysql};
	my $sql_cmd = "SHOW COLUMNS FROM `".$class->tablename."`";
	my $sth = $class->{DB}->execute($sql_cmd);
	while (my $row = $sth->fetchrow_hashref) {
		next unless lc($row->{Field}) eq lc($field);
		return 1;
		}
	return 0;
	}

sub is_field_generated {
	my $class = shift;
	my $field = shift;
	return ($class->{DB}->is_table_field_generated($class->tablename, $field));
	}

sub update {
	my $class	= shift;
	my $info	= shift; # reference to hash
	if (defined($class->check_info_diff($info))) {
		$class->load_info($class->check_info_diff($info));
		$class->update_info;
		}
	}

sub update_info {
	my $class = shift;
	my $dbh = $class->{DB}->{mysql};
	my ($info, $config) = $class->get_info;
	my $id = $class->get_id;
	die "Could not find id field value upon update" unless defined $id;
	
	my @fields = $class->get_field_dic;
	my @tmp;
	foreach my $arg (@fields) {
		next if $class->is_field_pk($arg);
		next if $class->is_field_generated($arg);
		push @tmp, $arg;
		}
	@fields = @tmp;
	my @request;
	foreach my $arg (@fields) {
		my $field_name = lc($arg);
		my $value;
		if (defined $class->info->{$field_name}) {
			$value = Atlas::prepare_str_for_insert($class->info->{$field_name});
			} else {
			$value = "NULL";
			}
		push (@request, "$field_name = $value");
		}
	my $sql_cmd = "UPDATE `".$class->tablename."` SET ".
		join(", ", @request)." where ".$class->id_field." = '$id';";
	my $sth = $class->{DB}->execute($sql_cmd);
	return 0;
	}

sub insert {
        my $class = shift;
        my $dbh = $class->{DB}->{mysql};
        my ($info, $config) = $class->get_info;
	
	my @fields = $class->get_field_dic;
	my @request_fields;
	my @request_values;
	# Manually set auto-incremented values
	foreach my $arg (@fields) {
		$arg = lc($arg);
		if ($class->is_field_ai($arg)) {
			$class->info->{$arg} = $class->field_next_value($arg);
			}
		}
	foreach my $arg (@fields) {
		next if $class->is_field_generated($arg);
		my $field_name = lc($arg);
		my $field_value;
		next unless defined($class->info->{$field_name});
		$field_value = Atlas::prepare_str_for_insert($class->info->{$field_name});
		push (@request_fields, $field_name);
		push (@request_values, $field_value);
		}
	my $sql_cmd = "INSERT INTO `".$class->tablename."` (".
		join(", ", @request_fields).") VALUES (".
		join(", ", @request_values).");";
	my $sth = $class->{DB}->execute($sql_cmd);
	return ($sth->{mysql_insertid});
	}

sub meta {
	my $class = shift;
	return $class->{meta};
	}

sub info {
	my $class = shift;
	return $class->{info};
	}

sub config {
	my $class = shift;
	return $class->{DB}->{'global_config'};
	}

sub get_info {
	my $class = shift;
	my $info = $class->info;
	my $config = $class->config;
	
	die "Undefined Database config\n" unless defined $info;
	die "Undefined info\n" unless defined $config;

	return ($info, $config);
	}

sub get_id {
	my $class = shift;
	my $id_field = $class->id_field;
	my $id = $class->info->{$id_field};
	return undef unless defined $id;
	return $id;
	}


sub fetch_info {
	my $class = shift;
	my $id = shift;
	my $dbh = $class->{DB}->{mysql};
	unless (defined($id)) {
		$id = $class->get_id;
		die "Id field for table ".$class->tablename." is not defined\n" unless defined $id;
		}
	my %info;
	my @fields = $class->get_field_dic;
	my $sql_cmd = "select " . join(", ", @fields) . " from `".$class->tablename."` where ".$class->id_field." = '$id'";
	my $sth = $class->{DB}->execute($sql_cmd);
	my $counter = 0;
	while (my $row = $sth->fetchrow_arrayref) {
		++$counter;
		for (my $i = 0; $i < scalar @fields; $i++) {
			$info{$fields[$i]} = encode('utf8', $$row[$i])
			}
		}
	unless ($counter eq 1) {
		print STDERR "Return $counter rows from database specified with the ",$class->id_field," $id\n" if $verbose;
		return 1;
		}
	$class->{info} = \%info;
	}

sub get_field_dic {
	my $class = shift;
	return $class->{DB}->get_table_field_dic($class->tablename);
	}

sub fetch {
	my $class = shift;
	my $DB = shift;
	my $id = shift;
	
	my $self = $class->new;
	$self->connect($DB);
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
	}

sub insert_row {
	my $class = shift;
	my $DB = shift;
	my $info = shift;
	my $new_row = $class->new;
	$new_row->connect($DB);
	$new_row->load_info($info);
	my $insert_id = $new_row->insert;
	return $insert_id;
	}

# Сабрутина для проверки соответствия идентичности двух хэшей.
# Используется для того чтобы проверить как новые поля в таблице (например, $barcode->info) отличаются от потенциально новых
# Возвращает хэш в котором отражены новые поля. Если хэш пустой - значит никакие поля не обновлены
sub check_info_diff {
	my $class	= shift;
	my $info	= shift;
	return Atlas::check_info_diff($class->{DB}, $class->tablename, $info, $class->info);
	}

sub assignGDFile {
	my $class = shift;
	my $key = shift;
	
	my $file = $class->GDFile;
	if (defined($file)) {
		$file->delete;
		}
	my $info;
	$info->{filekey} = $key;
	$info->{filetype} = $class->gdfiletype;
	$info->{($class->id_field)} = $class->get_id;
	return (Table::GDFile->fetch($class->{DB}, Table::GDFile->insert_row($class->{DB}, $info)));
	}
































1;
