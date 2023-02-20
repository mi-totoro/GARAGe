package Case;

use warnings;
use strict;
use Dir::Self;
use lib __DIR__;

use Data::Dumper;
use Aoddb;
use Atlas;
use Barcode;
use Patient;
use Storable 'dclone';
use File::Basename;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Switch;
my $local_path = __DIR__ . '/';


our @ISA	= qw/ Exporter AODDB/;
our @EXPORT	= qw/ $verbose /;
our $verbose	= 0;

sub new {
	my $class = shift;
	my $self = {};
	return (bless $self, $class);
	}

sub connect {
	my $class = shift;
	my $db = shift;
	
	$class->{'DB'} = $db;
	}

sub Patient {
	my $class = shift;
	my $patient_id = (Atlas::parse_case($class->get_id))[0];
	my $patient = Patient->fetch($class->{DB}, $patient_id);
	return $patient;
	}

sub load_info {
	my $class = shift;
	my $info  = shift;
	my $result;
	my @cols = $class->get_field_dic;
	OUTER_LOAD_INFO: foreach my $key (keys %{$info}) {
		foreach my $arg (@cols) {
			my $dic = $arg; $dic = lc($dic); $dic =~ s/_//g;
			my $cur = $key; $cur = lc($cur); $cur =~ s/_//g;
			next OUTER_LOAD_INFO if $cur eq 'casename';
			if ($dic eq $cur) {
				$class->{info}->{$arg} = $info->{$key};
				next OUTER_LOAD_INFO;
				}
			}
		print STDERR "WARNING: field $key was not found in mysql database\n" if $verbose;
		}
	return 0;
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
	die "Undefined run info\n" unless defined $config;
	
	return ($info, $config);
	}

sub get_field_dic {
	my $class = shift;
	my $table = shift;
	$table = "Case" unless defined $table;
	my $db = $class->{DB};
	my $dbh = $class->{DB}->{mysql};
	my $sql_cmd = "SELECT * FROM `$table` WHERE 1=0";
	my $sth = $dbh->prepare($sql_cmd);
	eval {$sth->execute};
	if ($@) {
		print STDERR "$@" if $verbose;
		print STDERR "Could not execute sql command:\n$sql_cmd <- error\n" if $verbose;
		die;
		}
	my @cols = @{$sth->{NAME_lc}};
	$sth->finish;
	return @cols;
	}

sub get_id {
	my $class = shift;
	my $case_name = $class->info->{casename};
	die "case Id is not defined\n" unless defined $case_name;
	return $case_name;
	}

sub get_patient_id {
	my $class = shift;
	my $id = $class->info->{patientid};
	die "patient Id is not defined\n" unless defined $id;
	return $id;
	}

sub generate_name {
	my $class = shift;
	my $case_id = $class->{info}->{caseid};
	my $pt_id = $class->{info}->{patientid};
	return 0 unless defined $case_id;
	return 0 unless defined $pt_id;
	$class->info->{casename} = "$pt_id-$case_id";
	}

sub insert_case {
	my $class = shift;
	my $dbh = $class->{DB}->{mysql};
	my ($info, $config) = $class->get_info;
	
	my @fields = $class->get_field_dic;
	my @tmp;
	foreach my $arg (@fields) {
		next if $arg eq 'casename';
		push @tmp, $arg;
		}
	@fields = @tmp;
	my $field_str = join(", ", @fields);
	my @values;
	foreach my $arg (@fields) {
		my $field_name = lc($arg);
		my $value;
		if (defined $class->info->{$field_name}) {
			$value = Atlas::prepare_str_for_insert($class->info->{$field_name});
			} else {
			$value = "NULL";
			}
		push (@values, $value);
		}
	my $value_str = join(", ", @values);
	
	my $sql_cmd = "INSERT INTO `Case` ($field_str) VALUES ($value_str);";
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

sub drive_folder {
	my $class = shift;
	my $GDFile = $class->GDFile;
	if (defined($GDFile)) {
		return $GDFile->info->{filekey};
		} else {
		my $barcode_id = $class->{internalbarcode}->{internalbarcodeid};
		my $root_id = $class->Patient->drive_folder;
		return $class->{DB}->search_drive_folder($barcode_id, $root_id);
		}
	}

sub drive_folder_link {
	my $class = shift;
	my $folder = $class->drive_folder;
	return undef unless defined $folder;
	$folder = "=HYPERLINK(\"https://drive.google.com/drive/u/0/folders/$folder\";\"".$class->get_id."\")";
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
	$info->{filetype} = 'folder';
	$info->{casename} = $class->get_id;
	return (Table::GDFile->insert_row($class->{DB}, $info));
	}

sub GDFile {
	my $class = shift;
	
	my $file = Table::GDFile->new;
	my $sth = "SELECT ".$file->id_field." FROM `".$file->tablename."` WHERE casename='".$class->get_id."' and fileType='folder' limit 1;";
	$sth = $class->{DB}->execute_select_single($sth);
	return undef unless defined $sth;
	$file = Table::GDFile->fetch($class->{DB}, $sth);
	return $file;
	}

sub InternalBarcode {
	my $class = shift;
	my $IB = Table::InternalBarcode->new;
	my $sth = "SELECT ".$IB->id_field." FROM `".$IB->tablename."` WHERE caseid = '".$class->info->{caseid}."' and patientid = '".$class->info->{patientid}."';";
	$sth = $class->{DB}->execute_select_single($sth);
	return undef unless defined($sth);
	return (Table::InternalBarcode->fetch($class->{DB}, $sth));
	}	

sub insert_internalBarcode {
        my $class = shift;
        my $dbh = $class->{DB}->{mysql};
        my ($info, $config) = $class->get_info;

        my @fields = $class->get_field_dic('InternalBarcode');
        my $field_str = join(", ", @fields);
        my @values;
	my $data = $class->{internalbarcode};
	$data->{caseid} = $class->info->{caseid};
	$data->{patientid} = $class->info->{patientid};
        foreach my $arg (@fields) {
                my $field_name = lc($arg);
                my $value;
                if (defined $data->{$field_name}) {
                        $value = Atlas::prepare_str_for_insert($data->{$field_name});
                        } else {
                        $value = "NULL";
                        }
                push (@values, $value);
                }
        my $value_str = join(", ", @values);

        my $sql_cmd = "INSERT INTO `InternalBarcode` ($field_str) VALUES ($value_str);";
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
	$class->insert_case;
	$class->insert_internalBarcode if (defined ($class->{internalbarcode}->{internalbarcodeid}));
	}

sub barcodes {
	my $class = shift;
	my $id = $class->get_id;
	my $caseId = Atlas::grep_case_id($id);
	my $patientId = Atlas::grep_patient_id($id);
	my $dbh = $class->{DB}->{mysql};
	
	my @barcode;
	my $sql_cmd = "select barcodename from `Barcode` where patientid = '$patientId' and caseid = '$caseId';";
	my $sth;
	$sth = $dbh->prepare($sql_cmd) or return 1;
	eval {$sth->execute};
	if ($@) {
		print STDERR "$@" if $verbose;
		print STDERR "Could not execute sql command:\n$sql_cmd <- error\n" if $verbose;
		die;
		} else {
		while (my $row = $sth->fetchrow_arrayref) {
			push (@barcode, $class->{DB}->Barcode($$row[0]));
			}
		}
	return @barcode;
	}

sub fetch_info_by_internal_barcode {
	my $class = shift;
	my $id    = shift;
	my $dbh = $class->{DB}->{mysql};
	my %info;
	my @fields = $class->get_field_dic;
	my @fields_cmd = map {"`Case`.$_"} @fields;
	my $sql_cmd = "select " . join(", ", @fields_cmd) . " from `Case` INNER JOIN InternalBarcode ON (`Case`.patientId = InternalBarcode.patientId and `Case`.caseId = InternalBarcode.caseId) where internalBarcodeId = '$id';";
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
		print STDERR "Return $counter rows from database specified with the case name $id\n" if $verbose;
		return 1;
		}
	$class->{info} = \%info;
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
	my $sql_cmd = "select " . join(", ", @fields) . " from `Case` where casename = '$id'";
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
		if ($class->fetch_info_by_internal_barcode($id)) {return 1}
		print STDERR "Return $counter rows from database specified with the case name $id\n" if $verbose;
		return 1;
		}
	$class->{info} = \%info;
	}

sub fetch_internalBarcode {
        my $class = shift;
	my ($patient_id, $case_id) = Atlas::parse_case($class->get_id);
	return 1 unless defined $patient_id;
	return 1 unless defined $case_id;
        my $dbh = $class->{DB}->{mysql};
        my %internal_barcode;
        my @fields = $class->get_field_dic("InternalBarcode");
        my $sql_cmd = "select " . join(", ", @fields) . " from `InternalBarcode` where caseId = '$case_id' and patientId = '$patient_id';";
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
                                $internal_barcode{$fields[$i]} = encode('utf8', $$row[$i])
                                }
                        }
                }
        unless ($counter eq 1) {
		#print STDERR "3Return $counter rows from database specified with the case name $patient_id-$case_id\n" if $verbose;
                return 1;
                }
        $class->{internalbarcode} = \%internal_barcode;
        }


sub fetch {
	my $class = shift;
	my $DB = shift;
	my $id = shift;
	
	
	my $self = $class->new;
	eval {$self->connect($DB)};
	eval {$self->fetch_info($id)};
	eval {$self->fetch_internalBarcode;};
	eval {$self->get_id};
	if ($@) {
		print STDERR "$@" if $verbose;
		return undef;
		} else {
		return $self;
		}
	}

sub generate_id {
	my $class = shift;
	my $dbh = $class->{DB}->{mysql};
	
	my @ids = qw(0);
	my $id = $class->info->{caseid};
	my $pt_id = $class->info->{patientid};
	if (defined $id) {
		print STDERR "Could not generate Id. Case is already assigned with id : '$id'" if $verbose;
		return 1;
		}
	unless(defined($pt_id)) {
		print STDERR "Could not generate Id. Patient id is not defined : '$id'" if $verbose;
		return 1;
		}
	my $sql_cmd = "select caseId from `Case` where patientId = '$pt_id';";
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

sub assign_id {
	my $class = shift;
	my $id = shift;
	$class->{info}->{caseid} = $id;
	$class->generate_name;
	}

sub select_property_table {
	my $class = shift;
	my $package_name = shift;
	my $id = $class->get_id;
	my $dbh = $class->{DB}->{mysql};
	my $table_test = $package_name->new;
	my $sql_cmd = "select ".$table_test->id_field." from `".$table_test->tablename."` where casename='$id';";
	my $result_id = $class->{DB}->execute_select_single($sql_cmd);
	return undef unless defined $result_id;
	my $Result = $package_name->fetch($class->{DB}, $result_id);
	return $Result;
	}

sub BaselineStatus {
	my $class = shift;
	return $class->select_property_table("Table::BaselineStatus");
	}

sub PathoResult {
	my $class = shift;
	return $class->select_property_table("Table::PathoResult");
	}

sub ClinicalInterpretation {
	my $class = shift;
	return $class->select_property_table("Table::ClinicalInterpretation");
	}

sub Case {
	my $class = shift;
	return $class;
	}

sub check_info_diff {
	my $class	= shift;
	my $info_new	= shift;
	return Atlas::check_info_diff($class->{DB}, "Case", $info_new, $class->info);
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
	my $sql_cmd = "UPDATE `Case` SET ".
		join(", ", @request)." where casename = '$id';";
	my $sth = $class->{DB}->execute($sql_cmd);
	return 0;
	}

sub is_field_pk {
	my $class = shift;
	my $field = shift;
	return ($class->{DB}->is_table_field_pk("Case", $field));
	}

sub is_field_exist {
	my $class = shift;
	my $field = shift;
	my $dbh = $class->{DB}->{mysql};
	my $sql_cmd = "SHOW COLUMNS FROM `Case`";
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
	return ($class->{DB}->is_table_field_generated("Case", $field));
	}

sub update {
	my $class       = shift;
	my $info        = shift; # reference to hash
	if (defined($class->check_info_diff($info))) {
		print STDERR "HERE\n";
		$class->load_info($class->check_info_diff($info));
		$class->update_info;
		}
	}

sub update_profile_date {
	my $class	= shift;
	
	return undef unless defined($class->Case->PRoute->info->{filekey});
	my $date = Atlas::wrap_python("python $local_path//../scripts/python/SS_get_Cell.py ".$class->Case->PRoute->info->{filekey}." Requisition B4");
	my $info = dclone $class->info;
	if ($date =~ /^(\d\d\d\d)\.(\d{1,2})\.(\d{1,2})$/) {
		$info->{"profiledateyear"} = $1;
		$info->{"profiledatemonth"} = $2;
		$info->{"profiledateday"} = $3;
	} elsif ($date =~ /^(\d\d\d\d)\.(\d{1,2})$/) {
		$info->{"profiledateyear"} = $1;
		$info->{"profiledatemonth"} = $2;
		$info->{"profiledateday"} = undef;
	} elsif ($date =~ /^(\d\d\d\d)$/) {
		$info->{"profiledateyear"} = $1;
		$info->{"profiledatemonth"} = undef;
		$info->{"profiledateday"} = undef;
	} elsif (lc($date) eq 'n/a') {
		$info->{"profiledateyear"} = undef;
		$info->{"profiledatemonth"} = undef;
		$info->{"profiledateday"} = undef;
	} elsif (lc($date) eq 'na') {
		$info->{"profiledateyear"} = undef;
		$info->{"profiledatemonth"} = undef;
		$info->{"profiledateday"} = undef;
	} elsif (lc($date) eq '') {
		$info->{"profiledateyear"} = undef;
		$info->{"profiledatemonth"} = undef;
		$info->{"profiledateday"} = undef;
	} else {
		$info->{"profiledateyear"} = undef;
		$info->{"profiledatemonth"} = undef;
		$info->{"profiledateday"} = undef;
		}
	$class->update($info);
	}

sub VariantZygosity { # определяет зиготность варианта на основании результатов среди всех баркодов (wt - если не обнаружен)
	my $class = shift;
	my $mutation_name = shift; # имя мутации в соответствии с chr1:12378G>A

	my $Mutation = $class->{DB}->Mutation($mutation_name);
	return 'wt' unless defined $Mutation;
	my $sql_cmd = "select zygosityValidated, zygosityCurated, zygosityAutomatic from MutationResult INNER JOIN Analysis ON Analysis.analysisName = MutationResult.analysisName INNER JOIN Barcode ON Barcode.barcodeName = Analysis.barcodeName INNER JOIN `Case` ON `Case`.caseId = Barcode.caseId AND `Case`.patientId = Barcode.patientId where Analysis.analysisRole = 'Major' AND `Case`.caseName = '".$class->get_id."' AND MutationResult.mutationId = '".$Mutation->get_id."' ORDER BY IF(ISNULL(zygosityValidated),1,0), IF(ISNULL(zygosityCurated),1,0), IF(ISNULL(zygosityAutomatic),1,0) ASC, Barcode.dataAcquisitionDate DESC";
	my $sth = $class->{DB}->execute($sql_cmd);
	while (my $row = $sth->fetchrow_arrayref) {
		if (defined($$row[2])) {return $$row[2];}
		if (defined($$row[1])) {return $$row[1];}
		if (defined($$row[0])) {return $$row[0];}
		}
	return "wt";
	}

sub parseVariantText { # RETURN HASHREF {"message" => undef/"text", "result" => $MutationRule}
	my $class = shift;
	my $text = shift;
	my $config = shift; #HASHREF; {"forcewt" => "1/0"}. IF 1 - wt forced for mutation rule if $text has variant format (chr:posref>alt); IF 0 (DEFAULT) - error on wild type if $text is variant
	unless (defined($config)) {
		$config = {"forcewt" => 0};
		}
	my $result;
	$result->{result} = undef;
	$result->{message} = '';
	my $Mutation;
	my $zygosity;
	my $mutationRule_name;
	$text = '' unless defined $text;
	if (Atlas::isVariantFormat($text)) {
		$Mutation = $class->{DB}->Mutation($text);
		unless (defined($Mutation)) {
			$result->{message} = "Unknown variant specified: '$text'";
			return $result;
			}
		my $zygosity = $class->VariantZygosity($Mutation->name);
		if (($zygosity =~ /wt/)and($config->{forcewt} eq 0)) {
			$result->{message} = "Sample is wild type for the variant $text; possible error in mutation spelling. If no, define mutation rule strictly: '$text:wt'";
			return $result;
			}
		$mutationRule_name = "$text:$zygosity";
		} elsif (Atlas::isVariantRuleFormat($text)) {
		$mutationRule_name = $text;
		} else {
		$result->{message} = "Could not parse: '$text' nor variant format, nor variantRule format. Either syntax error or variant is unknown";
		return $result;
		}
	my $MutationRule = Table::MutationRule->forceFetch($class->{DB}, $mutationRule_name);
	if (defined($MutationRule)) {
		$result->{result} = $MutationRule;
		} else {
		$result->{result} = undef;
		$result->{message} = "Could not identify MutationRule: '$text'. Either syntax error or mutation is unknown";
		}
	return $result;
	}

sub parseCNVText { # RETURN HASHREF {"message" => undef/"text", "result" => $CNV}
	my $class = shift;
	my $text = shift;
	
	my $config = shift; #HASHREF; {"forcewt" => "1/0"}. IF 1 - wt forced for mutation rule if $text has variant format (chr:posref>alt); IF 0 (DEFAULT) - error on wild type if $text is variant
	unless (defined($config)) {
		$config = {"forcewt" => 0};
		}
	my $result;
	$result->{result} = undef;
	$result->{message} = '';
	my $CNV;
	my $status;
	$text = '' unless defined $text;
	if (lc($text) =~ /(\S+):(amp|del)/) {
		my $gene = $1;
		my $Gene = $class->{DB}->Gene($gene);
		unless (defined $Gene) {
			$result->{message} = "Gene ($text) unknown";
			return $result;
			}
		my $type = $2;
		foreach my $Barcode ($class->barcodes) {
			next unless defined $Barcode->major_AN;
			next unless defined $Barcode->major_AN->CNV_status_by_gene($Gene);
			if ($Barcode->major_AN->CNV_status_by_gene($Gene)->CNV->info->{'type'} eq $type) {
				$result->{result} = $Barcode->major_AN->CNV_status_by_gene($Gene)->CNV;
				return $result;
				}
			}
		$result->{message} = "Variant ($text) not found in sample";
		return $result;
		}
	$result->{message} = 'Unknown variant format';
	return $result;
	}

sub CDate {
	my $class = shift;
	my $CDate = '';
	if ((defined($class->info->{profiledateyear}))and(not(defined($class->info->{profiledatemonth})))) {
		$CDate = $class->info->{profiledateyear} . ' год';
		} elsif ((defined($class->info->{profiledateyear}))and((defined($class->info->{profiledatemonth})))and(not(defined($class->info->{profiledateday})))) {
		switch($class->info->{profiledatemonth}) {
			case 1	 { $CDate = 'январь ' . $class->info->{profiledateyear} . ' года' }
			case 2   { $CDate = 'февраль ' . $class->info->{profiledateyear} . ' года' }
			case 3   { $CDate = 'март ' . $class->info->{profiledateyear} . ' года' }
			case 4   { $CDate = 'апрель ' . $class->info->{profiledateyear} . ' года' }
			case 5   { $CDate = 'май ' . $class->info->{profiledateyear} . ' года' }
			case 6   { $CDate = 'июнь ' . $class->info->{profiledateyear} . ' года' }
			case 7   { $CDate = 'июль ' . $class->info->{profiledateyear} . ' года' }
			case 8   { $CDate = 'август ' . $class->info->{profiledateyear} . ' года' }
			case 9   { $CDate = 'сентябрь ' . $class->info->{profiledateyear} . ' года' }
			case 10  { $CDate = 'октябрь ' . $class->info->{profiledateyear} . ' года' }
			case 11  { $CDate = 'ноябрь ' . $class->info->{profiledateyear} . ' года' }
			case 12  { $CDate = 'декабрь ' . $class->info->{profiledateyear} . ' года' }
			}
		} elsif ((defined($class->info->{profiledateyear}))and((defined($class->info->{profiledatemonth})))and((defined($class->info->{profiledateday})))) {
			$CDate = (length($class->Case->info->{'profiledateday'}) < 2 ? '0' : '').$class->Case->info->{'profiledateday'}.'.'.(length($class->Case->info->{'profiledatemonth'}) < 2 ? '0' : '').$class->Case->info->{'profiledatemonth'}.'.'.$class->Case->info->{'profiledateyear'};
		}
	return $CDate;
	}

sub mutationResults { # grep all MutationResult from all sequenced barcodes. Single MutationResult for each Mutation detected across all barcodes. In case of overlap (same mutation detected in several barcodes) prioretization rules are applied (see code).
	my $class = shift;
	my $Case = $class;
	my %mutationResults; # Hash; keys - mutationId from `Mutation` table; values: {"AF" : allele frequency from MutationResult, "DP" : depth of coverage from MutationResult, "QC" : result from LibraryQC table, "MR" : variable class MutationResult}; see code for prioritization rules;
	foreach my $Barcode ($Case->barcodes) {
		next unless defined $Barcode->major_AN;
		my $Analysis = $Barcode->major_AN;
		mutationResults_INNER: foreach my $MutationResult ($Analysis->mutationResults) {
			my $current;
			$current->{AF} = $MutationResult->info->{allelefrequency};
			$current->{DP} = $MutationResult->info->{depth};
			$current->{QC} = Table::LibraryQC->fetch($class->{DB}, $Barcode->get_id)->info->{result};
			$current->{MR} = $MutationResult;
			if (defined($mutationResults{$MutationResult->info->{mutationid}})) {
				my $previous = $mutationResults{$MutationResult->info->{mutationid}};
				# PRIORETIZATION RULES::::BEGIN
				if ((lc($current->{QC}) eq 'pass')and(lc($previous->{QC}) eq 'fail')) {
					$mutationResults{$MutationResult->info->{mutationid}} = $current;
					next mutationResults_INNER;
					}
				if (($current->{AF} > 0.05)and($previous->{AF} < 0.05)) {
					$mutationResults{$MutationResult->info->{mutationid}} = $current;
					next mutationResults_INNER;
					}
				if ($current->{DP} > $previous->{DP}) {
					$mutationResults{$MutationResult->info->{mutationid}} = $current;
					next mutationResults_INNER;
					}
				# PRIORETIZATION RULES::::END
				} else {
				$mutationResults{$MutationResult->info->{mutationid}} = $current;
				}
			}
		}
	return (map {$mutationResults{$_}->{MR}} keys %mutationResults);
	}

sub CNVResults { # grep all MutationResult from all sequenced barcodes. Single MutationResult for each Mutation detected across all barcodes. In case of overlap (same mutation detected in several barcodes) prioretization rules are applied (see code).
	my $class = shift;
	my $Case = $class;
	my %CNVResults; # Hash; keys - mutationId from `Mutation` table; values: {"AF" : allele frequency from MutationResult, "DP" : depth of coverage from MutationResult, "QC" : result from LibraryQC table, "MR" : variable class MutationResult}; see code for prioritization rules;
	foreach my $Barcode ($Case->barcodes) {
		next unless defined $Barcode->major_AN;
		my $Analysis = $Barcode->major_AN;
		mutationResults_INNER: foreach my $CNVR ($Analysis->CNVResults) {
			my $current;
			$current->{FRACTION} = $CNVR->info->{fraction};
			$current->{DEPTH} = $CNVR->info->{depth};
			$current->{TYPE} = $CNVR->CNV->info->{type};
			$current->{QC} = Table::LibraryQC->fetch($class->{DB}, $Barcode->get_id)->info->{result};
			$current->{CNVR} = $CNVR;
			if (defined($CNVResults{$CNVR->info->{cnvid}})) {
				my $previous = $CNVResults{$CNVR->info->{cnvid}};
				# PRIORETIZATION RULES::::BEGIN
				if ((lc($current->{QC}) eq 'pass')and(lc($previous->{QC}) eq 'fail')) {
					$CNVResults{$CNVR->info->{cnvid}} = $current;
					next mutationResults_INNER;
					}
				# PRIORETIZATION RULES::::END
				} else {
				$CNVResults{$CNVR->info->{cnvid}} = $current;
				}
			}
		}
	return (map {$CNVResults{$_}->{CNVR}} keys %CNVResults);
	}	

sub generate_requisition { # Создать шаблон направления (google spreadsheet в папке пациента на google drive)
	my $class = shift;
	my $drive_file_name = "Направление ".($class->Patient->info->{patientfamilyname} || ($class->InternalBarcode ? $class->InternalBarcode->get_id : 'Main'));
	my $spreadsheet_key = $class->{DB}->{GD}->file_create($drive_file_name, "application/vnd.google-apps.spreadsheet", $class->GDFile->info->{filekey});

	my $template_key = $class->{DB}->config->{drive}->{files}->{requisition_template}->{latest}; # Определяем текущую версию шаблона
	$template_key = $class->{DB}->config->{drive}->{files}->{requisition_template}->{$template_key}->{key}; # Получаем ключ spreadsheet текущей версии шаблона

	my $response = Atlas::wrap_python("python $local_path/../scripts/python/SS_sheet_copy.py $spreadsheet_key $template_key"); # Копируется sheet из шаблона

	#my $spreadsheet = $class->{DB}->spreadsheet($spreadsheet_key);
	#my $worksheet = $spreadsheet->worksheet( { title => 'Sheet1' } ); # закомментировано, потому что это на старой версии API, которая отвалилась
	#$worksheet->delete; # закомментировано, потому что это на старой версии API, которая отвалилась
	my $version = $class->{DB}->config->{drive}->{files}->{requisition_template}->{latest};
	$class->PRoute_assign($spreadsheet_key, $version);
	}

sub PRoute {
	my $class = shift;

	my $file = Table::GDFile->new;
	my $sth = "SELECT ".$file->id_field." FROM `".$file->tablename."` WHERE casename='".$class->get_id."' and filetype='spreadsheet' limit 1;";
	$sth = $class->{DB}->execute_select_single($sth);
	return undef unless defined $sth;
	$file = Table::GDFile->fetch($class->{DB}, $sth);
	return $file;
	}

sub PRoute_assign {
	my $class = shift;
	my $key = shift;
	my $version = shift;

	my $file = $class->PRoute;
	if (defined($file)) {
		$file->delete;
		}
	my $info;
	$info->{filekey} = $key;
	$info->{filetype} = 'spreadsheet';
	$info->{casename} = $class->get_id;
	$info->{datatype} = 'requisition';
	$info->{templateversion} = $version;
	return (Table::GDFile->insert_row($class->{DB}, $info));
	}




















1;
