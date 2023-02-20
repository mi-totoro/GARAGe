package Patient;

use strict;
use warnings;
use Dir::Self;
use lib __DIR__;

use Aoddb;
use Atlas;
use Case;
use Barcode;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Data::Dumper;

our @ISA	= qw/ Exporter AODDB/;
our @EXPORT	= qw/ $verbose /;
our $verbose	= 1;

sub compare_date {
	my $date1 = shift;
	my $date2 = shift;
	my $y1; my $m1; my $d1;
	my $y2; my $m2; my $d2;
	if ($date1 =~ /(\d\d\d\d)-(\d\d)-(\d\d)/) {$y1 = $1; $m1 = $2; $d1 = $3;} else {return 0}
	if ($date2 =~ /(\d\d\d\d)-(\d\d)-(\d\d)/) {$y2 = $1; $m2 = $2; $d2 = $3;} else {return 0}
	if (($m1 eq '01')and($d1 eq '01')) {$m2 = $m1; $d2 = $d1;}
	if (($m2 eq '01')and($d2 eq '01')) {$m1 = $m2; $d1 = $d2;}
	if (($y1 eq $y2)and($m1 eq $m2)and($d1 eq $d2)) {
		return 0;
		} else {
		return 1;
		}
	}

sub search {
	my $class = shift;
	my ($info, $config) = $class->get_info;
	my $dbh = $class->{DB}->{mysql};

	my $cur_family = $info->{patientfamilyname};
	my $cur_given = $info->{patientgivenname};
	my $cur_add = $info->{patientaddname};
	my $cur_dob = $info->{patientdob};
	
	$cur_family = lc($cur_family) if (defined $cur_family);
	$cur_given = lc($cur_given) if (defined $cur_given);
	$cur_add = lc($cur_add) if (defined $cur_add);
	$cur_dob = lc($cur_dob) if (defined $cur_dob);
	
	my @found;
	my $sql_cmd = "select patientid, patientGivenName, patientFamilyName, patientAddName, patientDOB from Patient;";
	my $sth;
	$sth = $dbh->prepare($sql_cmd) or return 1;
	eval {$sth->execute};
	if ($@) {
		print STDERR "$@" if $verbose;
		print STDERR "Could not execute sql command:\n$sql_cmd <- error\n" if $verbose;
		die;
		} else {
		while (my $row = $sth->fetchrow_arrayref) {
			my $ref_given; my $ref_family; my $ref_add; my $ref_dob;
			$ref_given = lc(encode('utf8', $$row[1])) if (defined $$row[1]);
			$ref_family = lc(encode('utf8', $$row[2])) if (defined $$row[2]);
			$ref_add = lc(encode('utf8', $$row[3])) if (defined $$row[3]);
			$ref_dob = lc($$row[4]) if (defined $$row[4]);
			my $match = 0;
			if ((defined $ref_family)and(defined $cur_family)) {
				if ((defined($ref_dob))and(defined($cur_dob))) {
					$match = 1;
					} elsif((defined $ref_given)and(defined $cur_given)
						and(defined $ref_add)and(defined $cur_add)) {
						$match = 1;
						}
				}
			if ((defined $ref_family)and(defined($cur_family))) {$match = 0 if $ref_family ne $cur_family}
			if ((defined $ref_given)and(defined($cur_given))) {$match = 0 if $ref_given ne $cur_given}
			if ((defined $ref_add)and(defined($cur_add))) {$match = 0 if $ref_add ne $cur_add}
			if ((defined $ref_dob)and(defined($cur_dob))) {$match = 0 if compare_date($ref_dob, $cur_dob)}
			push @found, $$row[0] if $match eq 1;
			}
		}
	if (scalar @found > 0) {return \@found} else {return undef}
	}

sub new {
	my $class = shift;
	my $self = {};
	return (bless $self, $class);
	}

sub get_field_dic {
	my $class = shift;
	my $db = $class->{DB};
	my $dbh = $class->{DB}->{mysql};
	my $sql_cmd = "SELECT * FROM Patient WHERE 1=0";
	my $sth = $dbh->prepare($sql_cmd);
	eval {$sth->execute};
	if ($@) {
		undef $@;
		print STDERR "Could not execute sql command:\n$sql_cmd <- error\n" if $verbose;
		die;
		}
	my @cols = @{$sth->{NAME_lc}};
	$sth->finish;
	return @cols;
	}

sub connect {
	my $class = shift;
	my $db = shift;
	
	$class->{'DB'} = $db;
	return 0;
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
			next OUTER_LOAD_INFO if $cur eq 'patientid';
			if ($dic eq $cur) {
				$class->{info}->{$arg} = $info->{$key};
				next OUTER_LOAD_INFO;
				}
			}
		print STDERR "WARNING: field $key was not found in mysql database\n" if $verbose;
		}
	return 0;
	}

sub create_empty_info {
	my $class = shift;
	$class->{info} = {};
	return $class;
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
	my $run_id = $class->info->{patientid};
	die "Id is not defined\n" unless defined $run_id;
	return $run_id;
	}

sub insert {
	my $class = shift;
	my $dbh = $class->{DB}->{mysql};
	my ($info, $config) = $class->get_info;
	my $patient_id = $class->get_id;
	
	$patient_id = "'$patient_id'";
	my $patientGivenName = Atlas::prepare_str_for_insert($info->{patientgivenname});
	my $patientFamilyName = Atlas::prepare_str_for_insert($info->{patientfamilyname});
	my $patientAddName = Atlas::prepare_str_for_insert($info->{patientaddname});
	my $sexId = Atlas::prepare_str_for_insert($info->{sexid});
	my $patientDOB = 'NULL';
	if (defined($info->{patientdob})) {
		my $date = $info->{patientdob};
		if (Atlas::check_date_format($date)) {
			print STDERR "Can not parse date '$date'. Should follow YYYY-MM-DD format\n" if $verbose;
			return 1;
			}
		$patientDOB = "'$date'";
		}
	my $sql_cmd = "INSERT INTO `Patient` (patientid, patientGivenName, patientFamilyName, patientAddName, patientDOB, sexId) VALUES ($patient_id, $patientGivenName, $patientFamilyName, $patientAddName, $patientDOB, $sexId);";	
	my $sth;
	if ($sth = $dbh->prepare($sql_cmd)) {} else {
		die "Couldn't prepare statement: " . $dbh->errstr;
		}
	eval {$sth->execute};
	if ($@) {
		print STDERR "$@\n" if $verbose;
		print STDERR "Could not execute sql command:\n$sql_cmd <- error\n" if $verbose;
		die;
		} else {
		$class->{DB}->mysql_log($sql_cmd);
		}
	return 0;
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
	my $sql_cmd = "select " . join(", ", @fields) . " from Patient where patientid = $id;";
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
		print STDERR "Return $counter rows from database specified with the patient Id $id\n" if $verbose;
		return 1;
		}
	$class->{info} = \%info;
	
	}

sub full_name {
	my $class = shift;
	my @names = qw(patientfamilyname patientgivenname patientaddname);
	my @name;
	for (my $i = 0; $i < scalar @names; $i++) {
		my $value = $class->info->{$names[$i]};
		next unless defined $value;
		my @letters = split//, decode('utf8', $value);
		$letters[0] = uppercase($letters[0]);
		$value = join("", @letters);
		push (@name, $value);
		}
	return join(" ", @name);
	}

sub major_name {
	my $class = shift;
	my $major;
	if ((defined($class->info->{patientfamilyname}))and(length($class->info->{patientfamilyname}) > 1)) {
		$major = $class->info->{patientfamilyname};
		} elsif ((defined($class->info->{patientgivenname}))and(length($class->info->{patientgivenname}) > 1)) {
		$major = $class->info->{patientgivenname};
		} elsif ((defined($class->info->{patientaddname}))and(length($class->info->{patientaddname}) > 1)) {
		$major = $class->info->{patientaddname};
		} else {
		return "Unnamed";
		}
	my @letters = split//, decode('utf8', $major);
	$letters[0] = uppercase($letters[0]);
	$major = join("", @letters);
	return $major;
	}

sub uppercase {
	my $string = shift;
	my %abc = (
		"а"=>"А","б"=>"Б","в"=>"В","г"=>"Г",
		"д"=>"Д","е"=>"Е","ё"=>"Ё","ж"=>"Ж",
		"з"=>"З","и"=>"И","й"=>"Й","к"=>"К",
		"л"=>"Л","м"=>"М","н"=>"Н","о"=>"О",
		"п"=>"П","р"=>"Р","с"=>"С","т"=>"Т",
		"у"=>"У","ф"=>"Ф","х"=>"Х","ц"=>"Ц",
		"ч"=>"Ч","ш"=>"Ш","щ"=>"Щ","ъ"=>"Ъ",
		"ы"=>"Ы","ь"=>"Ь","э"=>"Э","ю"=>"Ю",
		"я"=>"Я",
		"a"=>"A","b"=>"B","c"=>"C","d"=>"D",
		"e"=>"E","f"=>"F","g"=>"G","h"=>"H",
		"i"=>"I","j"=>"J","k"=>"K","l"=>"L",
		"m"=>"M","n"=>"N","o"=>"O","p"=>"P",
		"q"=>"Q","r"=>"R","s"=>"S","t"=>"T",
		"u"=>"U","v"=>"V","w"=>"W","x"=>"X",
		"y"=>"Y","z"=>"Z");
	$string = uc($string);
	foreach my $letter (keys %abc) {
		$string =~ s/$letter/$abc{$letter}/g;
		}
	
	return $string;
	}

sub generate_id {
	my $class = shift;
	my $dbh = $class->{DB}->{mysql};
	
	my $id;
	$id = $class->info->{patientid};
	if (defined $id) {
		print STDERR "Could not generate Id. Patient is already assigned with id : '$id'" if $verbose;
		return 1;
		}
	my $sql_cmd = "select patientid from Patient;";
	my $sth;
	$sth = $dbh->prepare($sql_cmd) or return 1;
	my @ids;
	eval {$sth->execute};
	if ($@) {
		print STDERR "$@" if $verbose;
		print STDERR "Could not execute sql command:\n$sql_cmd <- error\n" if $verbose;
		die;
		} else {
		while (my $row = $sth->fetchrow_arrayref) {
			push (@ids, $$row[0]);
			}
		}
	OUTER: while (1) {
		$id = int(rand(99999));
		next if $id < 10000;
		map {my $local = $_;
			next OUTER if $local eq $id;
			} @ids;
		last;
		}
	
	return $id;
	}

sub drive_folder {
	my $class = shift;
	my $patient_id = $class->get_id;
	my $root_key = $class->{DB}->{global_config}->{drive}->{files}->{patient_data}->{key};
	return $class->{DB}->search_drive_folder($patient_id, $root_key);
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
	$info->{patientid} = $class->get_id;
	print STDERR "in3\n";
	return (Table::GDFile->insert_row($class->{DB}, $info));
	}

sub GDFile {
	my $class = shift;
	
	my $sth = "SELECT fileid FROM GDFile WHERE patientid='".$class->get_id."' limit 1;";
	$sth = $class->{DB}->execute_select_single($sth);
	return undef unless defined $sth;
	my $file = Table::GDFile->fetch($class->{DB}, $sth);
	return $file;
	}

sub new_case {
	my $class = shift;
	my $CS = Case->new;
	$CS->connect($class->{DB});
	$CS->load_info({'patientid' => $class->get_id});
	my $case_id = $CS->generate_id;
	$CS->assign_id($case_id);
	if ($CS->insert) {return undef};
	return $CS;
	}

sub cases {
	my $class = shift;
	my $id = $class->get_id;
	my $dbh = $class->{DB}->{mysql};
	
	my @case;
	my $sql_cmd = "select caseName from `Case` where patientid = '$id';";
	my $sth;
	$sth = $dbh->prepare($sql_cmd) or return 1;
	eval {$sth->execute};
	if ($@) {
		print STDERR "$@" if $verbose;
		print STDERR "Could not execute sql command:\n$sql_cmd <- error\n" if $verbose;
		die;
		} else {
		while (my $row = $sth->fetchrow_arrayref) {
			push (@case, $class->{DB}->Case($$row[0]));
			}
		}
	return @case;
	}

#sub get_next_case {
#	my $class = shift;
#	my $int = max(map {$_ = Atlas::slim_id(Atlas::grep_case_id($_->get_id))} $class->cases);
#	$int++;
#	if ($int =~ /(\d)/) {
#		$int = "0$int";
#		}
#	return $int;
#	}

sub fetch {
	my $class = shift;
	my $DB = shift;
	my $id = shift;
	
	my $self = $class->new;
	$self->connect($DB);
	$self->fetch_info($id);
	eval {$self->get_id};
	if ($@) {
		print STDERR "Could not fetch patient \n" if $verbose;
		print STDERR "$@\n" if $verbose;
		return undef;
		} else {
		return $self;
		}
#	return $self;
#	if (defined($self->{info})) {
#		return $self;
#		} else {
#		return undef;
#		}
	}

sub assign_id {
	my $class = shift;
	my $id = shift;
	$class->{info}->{patientid} = $id;
	}















1;
