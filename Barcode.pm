package Barcode;

use strict;
use warnings;
use Dir::Self;
use lib __DIR__;

use Data::Dumper;
use Aoddb;
use Atlas;
use File::Basename;
use Table::Analysis;
use Table::LibraryQC;
use File::Bam;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);

our @ISA = qw(Exporter);
our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub new {
	my $class = shift;
	my $self = {};
	$self->{meta} = {};
	$self->{info} = {};
	return (bless $self, $class);
	}

sub Case {
	my $class = shift;
	my $patient_id = (Atlas::parse_barcode($class->get_id))[0];
	my $case_id = (Atlas::parse_barcode($class->get_id))[1];
	my $case = $class->{DB}->Case("$patient_id-$case_id");
	return $case;
	}

sub analyses {
	my $class = shift;
	my $id = $class->get_id;
	my $dbh = $class->{DB}->{mysql};
	
	my @analyses;
	my $sql_cmd = "select analysisname from `Analysis` where barcodename = '$id';";
	my $sth;
	$sth = $dbh->prepare($sql_cmd) or return 1;
	eval {$sth->execute};
	if ($@) {
		print STDERR "$@" if $verbose;
		print STDERR "Could not execute sql command:\n$sql_cmd <- error\n" if $verbose;
		die;
		} else {
		while (my $row = $sth->fetchrow_arrayref) {
			push (@analyses, $class->{DB}->Analysis($$row[0]));
			}
		}
	return @analyses;
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
			$info->{caseid} = Atlas::grep_case_id($info->{$key});
			$info->{patientid} = Atlas::grep_patient_id($info->{$key});
			delete($info->{$key});
			}
		}
	my $result;
	my @cols = $class->get_field_dic;
	OUTER_LOAD_INFO: foreach my $key (keys %{$info}) {
		foreach my $arg (@cols) {
			my $dic = $arg; $dic = lc($dic); $dic =~ s/_//g;
			my $cur = $key; $cur = lc($cur); $cur =~ s/_//g;
			next OUTER_LOAD_INFO if $cur eq 'barcodename';
			if ($cur eq "libraryname") {
				$class->{meta}->{"libraryname"} = $info->{$key};
				next OUTER_LOAD_INFO;
				}
			if ($cur eq "librarypath") {
				$class->{meta}->{"librarypath"} = $info->{$key};
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

sub casename {
	my $class = shift;
	return undef unless defined $class->{info};
	return undef unless defined $class->{info}->{caseid};
	return undef unless defined $class->{info}->{patientid};
	my $case_id = $class->{info}->{caseid};
	my $patient_id = $class->{info}->{patientid};
	return "$patient_id-$case_id";
	}

sub is_folder_exist {
	my $class = shift;
	my ($info, $config) = $class->get_info;
	my $barcode_name = $class->get_id;
	
	my @dirs = (
		"$config->{data_path}->{barcodePath}/$barcode_name"
		);
	foreach my $arg (@dirs) {
		if (opendir(my $dir, "$arg")) {
			closedir $dir;
			} else {
			return 0;
			}
		}
	return 1
	
	}

sub check_folder_structure {
	my $class = shift;
	my ($info, $config) = $class->get_info;
	my $barcode_name = $class->get_id;

	return 1 if ($class->is_folder_exist eq 0);

	my @dirs = (
		"$config->{data_path}->{barcodePath}/$barcode_name",
		"$config->{data_path}->{barcodePath}/$barcode_name/raw"
		);
	map {my $destiny = $_;
		if (opendir(my $dir, "$destiny")) {
			closedir $dir;
			} else {
			return 1;
			}
		} @dirs;

	return 0;
	}

sub create_data_dir {
	my $class = shift;
	my ($info, $config) = $class->get_info;
	my $barcode_name = $class->get_id;

	my %log;
	my @dirs = (
		"$config->{data_path}->{barcodePath}/$barcode_name",
		"$config->{data_path}->{barcodePath}/$barcode_name/raw"
		);
	map {my $dir = $_;
		$log{$dir} = `mkdir -v $dir 2>&1`;
		chomp $log{$dir};
		print STDERR "$log{$dir}\n" if $verbose;
		} @dirs;
	
	my $f = 0;
	if ($class->check_folder_structure) {
		print STDERR "Could not correctly create run folder\n" if $verbose;
		for (my $i = scalar @dirs - 1; $i >= 0; $i--) {
			my $log_i = $dirs[$i];
			if ($log{$log_i} eq "mkdir: created directory '$log_i'") {
				print STDERR "Removing created fodler: $log_i\n" if $verbose;
				`rm -r $log_i`
				}
			};
		return 1;
		}
	return 0;
	}

sub Run {
	my $class = shift;
	my $barcode_name = $class->get_id;
	my $sql = "SELECT sequencingRunId FROM Barcode WHERE barcodeName = '$barcode_name';";
	my $run_id = $class->{DB}->execute_select_single($sql);
	return $class->{DB}->Run($run_id);
	}	

sub folder_remove {
	my $class = shift;
	my ($info, $config) = $class->get_info;
	my $barcode_name = $class->get_id;

	`rm -r $config->{data_path}->{barcodePath}/$barcode_name 2>&1`;
	if ($class->is_folder_exist eq 0) {
		print STDERR "Barcode data folder sucessfully removed (barcodeName : $barcode_name)\n" if $verbose eq 1;
		return 1;
		}
	return 0;
	}

sub upload_data { #move data from #meta fields to the corresponding barcode folder on disk
	my $class = shift;
	my ($info, $config) = $class->get_info;
	my $barcode_name = $class->get_id;
	
	my @copied;
	unless (defined $class->meta->{librarypath}) {
		print STDERR "No associated data found in meta atrributes\n" if $verbose eq 1;
		return 1;
		}
	unless (defined $class->meta->{libraryname}) {
		print STDERR "No associated data found in meta atrributes\n" if $verbose eq 1;
		return 1;
		}
	my $file = $class->meta->{librarypath} . "/" . $class->meta->{libraryname};
	my $destination = "$config->{data_path}->{barcodePath}/$barcode_name/raw/";
	if ($class->is_folder_exist eq 1) {
		print STDERR "Could not upload data. Associated barcode folder alreader exist at $destination\n" if $verbose;
		return 1;
		}
	die "Could not create barcode directory" if ($class->create_data_dir);
#	print STDERR "HERE\n";
	$destination = $destination . basename($file);
	my $log = `cp $file $destination 2>&1`; chomp $log;
	sleep(10);
#	print STDERR "HERE `2 - $destination`\n";
	if (open(my $fh, "<", $destination)) {
		close $fh;
		#print STDERR "HERE `3`\n";
		return 0;
		} else {
		print STDERR "Could not copy file\n$log\n" if $verbose;
		$class->folder_remove;
		#print STDERR "FUCKED `3`\n$log\n";
		return 1;
		}
	
	}

sub delete {
	my $class = shift;
	my $dbh = $class->{DB}->{mysql};
	
	my $id = $class->get_id;
	#my $sql_cmd = "delete from SequencingHistory where barcodeName = '$id';";
	#my $sth = $class->{DB}->execute($sql_cmd);
	my $sql_cmd = "delete from Barcode where barcodeName = '$id';";
	my $sth = $dbh->prepare($sql_cmd) or return 1;
	eval {$sth->execute};
	if ($@) {
		print STDERR "$@" if $verbose;
		print STDERR "Could not execute sql command:\n$sql_cmd <- error\n" if $verbose;
		$class->folder_remove;
		die;
		} else {
		$class->{DB}->mysql_log($sql_cmd);
		}
	print STDERR "Barcode $id removed from database\n" if $verbose;
	$class->folder_remove;
	return 0;
	}

sub assign_id {
	my $class = shift;
	my $id = shift;
	$class->{info}->{barcodeid} = $id;
	$class->generate_name;
	}

sub generate_name {
	my $class = shift;
	my $case_id = $class->{info}->{caseid};
	my $pt_id = $class->{info}->{patientid};
	my $bc_id = $class->{info}->{barcodeid};
	return 0 unless defined $case_id;
	return 0 unless defined $pt_id;
	return 0 unless defined $bc_id;
	$class->info->{barcodename} = "$pt_id-$case_id-$bc_id";
	}

sub update {
	my $class = shift;
	my $dbh = $class->{DB}->{mysql};
	my ($info, $config) = $class->get_info;
	my $barcode_name = $class->get_id;
	
	my @fields = $class->get_field_dic;
	my @tmp;
	foreach my $arg (@fields) {
		next if $arg eq 'barcodename';
		next if $arg eq 'patientid';
		next if $arg eq 'barcodeid';
		next if $arg eq 'caseid';
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
	my $sql_cmd = "UPDATE `Barcode` SET " . join(", ", @request) . " where barcodename = '$barcode_name';";
	my $sth;
	if ($sth = $dbh->prepare($sql_cmd)) {} else {
		die "Couldn't prepare statement: " . $dbh->errstr;
		}
	eval {$sth->execute};
	if ($@) {
		print STDERR "$@" if $verbose;
		print STDERR "Could not execute sql command:\n$sql_cmd <- error\n" if $verbose;
		die;
		} else {
		$class->{DB}->mysql_log($sql_cmd);
		}
	return 0;
	}

sub insert {
        my $class = shift;
        my $dbh = $class->{DB}->{mysql};
        my ($info, $config) = $class->get_info;
        my $barcode_name = $class->get_id;

	#my $case_id = Atlas::prepare_str_for_insert($info->{caseid});
	#my $pt_id   = Atlas::prepare_str_for_insert($info->{patientid});
	#my $bc_id   = Atlas::prepare_str_for_insert($info->{barcodeid});
	#my $panel_code = Atlas::prepare_str_for_insert($info->{panelcode});
	
	my @fields = $class->get_field_dic;
	my @request_fields;
	my @request_values;
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
	my $sql_cmd = "INSERT INTO `Barcode` (".
		join(", ", @request_fields).") VALUES (".
		join(", ", @request_values).");";
	
	my $sth = $class->{DB}->execute($sql_cmd);
	return ($sth->{mysql_insertid});
	}

sub is_field_ai {
	my $class = shift;
	my $field = shift;
	return ($class->{DB}->is_table_field_AI('Barcode', $field));
	}	

sub is_field_generated {
	my $class = shift;
	my $field = shift;
	return ($class->{DB}->is_table_field_generated('Barcode', $field));
	}

sub generate_id {
        my $class = shift;
        my $dbh = $class->{DB}->{mysql};

        my @ids = qw(0);
        my $id = $class->info->{barcodeid};
	my $case_id = $class->info->{caseid};
	my $pt_id = $class->info->{patientid};
        if (defined $id) {
		print STDERR "Could not generate Id. Barcode is already assigned with id : '$id'" if $verbose;
		return 1;
		}
	unless(defined($case_id)) {
		print STDERR "Could not generate Id. Case id is not defined : '$id'" if $verbose;
		return 1;
		}
	unless(defined($pt_id)) {
		print STDERR "Could not generate Id. Patient id is not defined : '$id'" if $verbose;
		return 1;
		}
	my $sql_cmd = "select barcodeId from Barcode where patientId = '$pt_id' and caseId = '$case_id'";
	my $sth;
	$sth = $dbh->prepare($sql_cmd) or return 1;
	eval {$sth->execute};
	if ($@) {
		print STDERR "$@" if $verbose;
		print STDERR "Could not execute sql command:\n$sql_cmd <- error\n" if $verbose;
		die;
		} else {
		while (my $row = $sth->fetchrow_arrayref) {
			if ($$row[0] =~ /^(\d+)$/) {
				my $id_cur = $$row[0];
				if ($id_cur =~ /^0(\d)$/) {
					push (@ids, $1);
					} else {
					push (@ids, $id_cur);
					}
				}
			}
		}
	my $result = max(@ids) + 1;
	if ($result =~ /^(\d)$/) {
		$result = "0$result";
		}
	return $result;
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

sub get_folder {
	my $class = shift;
	my ($info, $config) = $class->get_info;
	
	return undef unless defined ($config->{data_path}->{barcodePath});
	return undef unless defined ($info->{barcodename});

	my $folder = $config->{data_path}->{barcodePath};
	$folder = $folder . "/" . $info->{barcodename} . "/";
	return $folder;
	}

sub get_bam {
	my $class = shift;
	my @bam;
	return undef unless defined($class->get_folder);
	if (opendir(DIR, $class->get_folder . "/raw")) {
		while (my $file = readdir(DIR)) {
			next if $file eq '.';
			next if $file eq '..';
			if ($file =~ /\.bam$/) {
				push (@bam, $file);
				}
			}
		closedir(DIR)
		} else {return undef; die "Can not find raw folder\n"}
	return undef unless defined $bam[0];
#	die "Can not find bam file\n" unless defined $bam[0];
	die "Multiple BAM files found\n" if defined $bam[1];
	
	return $bam[0];
	}

sub bam {
	my $class = shift;
	if (defined($class->get_bam)) {
		return File::Bam->new($class->get_folder."/raw/".$class->get_bam);
		} else {
		return undef;
		}
	}

sub get_id {
	my $class = shift;
	my $barcode_name = $class->info->{barcodename};
	die "Id is not defined\n" unless defined $barcode_name;
	return $barcode_name;
	}


sub fetch_info {
	my $class = shift;
	my $id = shift;
	my $dbh = $class->{DB}->{mysql};
	unless (defined($id)) {
		$id = $class->get_id;
		}
	my %info;
	my @fields = $class->get_field_dic;
	my $sql_cmd = "select " . join(", ", @fields) . " from Barcode where barcodename = '$id'";
	my $sth;
	$sth = $dbh->prepare($sql_cmd) or return 1;
	my $counter = 0;
	eval {$sth->execute};
	if ($@) {
		print STDERR "$@" if $verbose;
		print STDERR "Could not execute sql command:\n$sql_cmd <- error\n" if $verbose;
		die;
		} else {
		while (my $row = $sth->fetchrow_arrayref) {
			++$counter;
			for (my $i = 0; $i < scalar @fields; $i++) {
				$info{$fields[$i]} = encode('utf8', $$row[$i])
				}
			}
		}
	unless ($counter eq 1) {
		print STDERR "Return $counter rows from database specified with the barcode name $id\n" if $verbose;
		return 1;
		}
	$class->{info} = \%info;
	}

sub get_field_dic {
	my $class = shift;
	return $class->{DB}->get_table_field_dic("Barcode");
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
		return $self;
		}
	}

sub new_analysis {
	my $class	= shift;
	my $info	= shift;
	$info = {} unless defined $info;
	
	my $analysis = Table::Analysis->new();
	$analysis->connect($class->{DB});
	foreach my $key (keys %{$info}) {
		$analysis->{info}->{lc($key)} = $info->{$key};
		}
	$analysis->info->{"barcodename"} = $class->get_id;
	$analysis->info->{"analysisid"} = $analysis->generate_id;
	eval {$analysis->insert};
	if ($@) {
		print STDERR "$@\n";
		return undef;
		}
	$analysis = $class->{DB}->Analysis($analysis->name);
	return $analysis;
	}

sub QC {
	my $class = shift;
	
	my $QC = Table::LibraryQC->new();
	$QC->connect($class->{DB});
	$QC->info->{barcodename} = $class->get_id;
	return $QC;
	}

sub major_AN {
	my $class = shift;
	foreach my $arg ($class->analyses) {
		next unless defined($arg->info->{analysisrole});
		if (lc($arg->info->{analysisrole}) eq 'major') {
			return $arg;
			}
		}
	return undef;
	}

sub gene_list {
	my $class = shift;
	my $type  = shift;
	my $panel = uc($class->info->{panelcode});
	my $geneListFile = $class->{DB}->{global_config}->{software}->{pipeline};
	my @result;
	if ($type) {
		$geneListFile = "$geneListFile/panel_info/$panel/$panel.gene.list.$type";
		} else {
		$geneListFile = "$geneListFile/panel_info/$panel/$panel.gene.list";
		}
	open (my $fh, "<$geneListFile");
	while (<$fh>) {
		chomp;
		push @result, $_;
		}
	close $fh;
	return @result;
	}	

sub panel_bed {
	my $class = shift;
	my $panel = uc($class->info->{panelcode});
	my $bedFile = $class->{DB}->{global_config}->{software}->{pipeline};
	$bedFile = "$bedFile/panel_info/$panel/$panel.designed.bed";
	return $bedFile;
	}

sub LibraryQC {
	my $class = shift;
	return Table::LibraryQC->fetch($class->{DB}, $class->get_id);
	}	

sub Panel {
	my $class = shift;
	my $panel = uc($class->info->{panelcode});
	return $class->{DB}->Panel($panel);
	}
























1;









