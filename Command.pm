package Command;

use strict;
#use warnings;
use Dir::Self;
use lib __DIR__;
use Fcntl qw(:flock SEEK_END);
use Moose;
use DateTime;
use feature "switch";
no if $] >= 5.018, warnings => qw( experimental::smartmatch );
use Aoddb;
use Encode;
use Data::Dumper;
my $local_path = __DIR__ . '/';


our @ISA = qw(Exporter);
our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;


before [qw(run prepare QC AN UPLOAD ANNOTATE ALL PREPARE)] => sub {
	my $self = shift;
	$self->line->err('');
	$self->line->response('');
	};

sub new {
	my $class = shift;
	my $self = {};
	$self->{config} = {};
	
	bless $self, $class;
	return $self;
	}

sub line {
	my $class = shift;
	return $class->{line};
	}

sub errstr {
	my $class = shift;
	print STDERR "",$class->line->err,"\n";
	}

sub connect {
	my $class = shift;
	my $line = shift;

	$class->{line} = $line;
	}

sub cmd {
	my $class = shift;
	return $class->{cmd};
	}

sub parse {
	my $class = shift;
	
	my $info = {};
	my $meta = {};
	$meta->{force_role} = 0;
	
	my @mas = split/\s+/, $class->cmd;
	$meta->{type} = $mas[0];
	OUTER: foreach my $arg (@mas[1..(scalar @mas - 1)]) {
		given ($arg) {
			when (/barcode'(\S+)'/) {
				$info->{barcode} = $1;
				$info->{barcodename} = $1;
				}
			when (/analysis'(\S+)'/) {
				$info->{analysis} = $1;
				$info->{analysisname} = $1;
				}
			when (/code'(\S+)'/) {
				$info->{code} = $1;
				$info->{analysiscode} = $1;
				}
			when (/role'(\S+)'/) {
				$info->{role} = $1;
				$info->{analysisrole} = $1;
				}
			when (/batch'(\S+)'/) {
				$info->{batch} = $1;
				$info->{analysisbatch} = $1;
				}
			when (/force_role/) {
				$meta->{force_role} = 1;
				}
			default {
				$info = undef;
				$meta = undef;
				$class->line->err(1);
				$class->generate_response("Failed to parse argument $arg");
				last OUTER;
				}
			}
		}
	$class->{info} = $info;
	$class->{meta} = $meta;
	}

sub _info {
	my $class = shift;
	my $result = '';
	
	foreach my $key (keys %{$class->{info}}) {
		if ($key eq 'barcodename') {
			$result = "$result -barcode'".$class->{info}->{$key}."'";
			}
		if ($key eq 'analysiscoode') {
			$result = "$result -code'".$class->{info}->{$key}."'";
			}
		if ($key eq 'analysisrole') {
			$result = "$result -role'".$class->{info}->{$key}."'";
			}
		if ($key eq 'analysisbatch') {
			$result = "$result -batch'".$class->{info}->{$key}."'";
			}
		}
	return $result;
	}

sub _meta {
	my $class = shift;
	my $result = '';
	
	foreach my $key (keys %{$class->{meta}}) {
		if ($key eq 'force_role') {
			$result = "$result -force_role'".$class->{meta}->{$key}."'";
			}
		}
	return $result;
	}

sub _cmd {
	my $class = shift;
	
	my $result = $class->{meta}->{type};
	$result = "$result ". $class->_info . " " . $class->_meta;
	return $result;
	}

sub parse_QC_log {
	my $file_name = shift;
	open (my $fh, "<", $file_name);
	my @lines = <$fh>;
	foreach my $arg (@lines) {
		chomp $arg;
		return 1 if ($arg =~ /^Quality\s+control\s+-\s+SUCCESS$/)
		}
	return 0;
	close $fh;
	}

sub QC {
	my $class = shift;
	my $seed = int(rand(1000000000000000000));
	my $logFile = $class->line->{DB}->config->{data_path}->{logPath} . "/analyzer/QC.$seed";
	my $barcode_name = $class->{info}->{barcode};
	my $bcode = $class->line->{DB}->Barcode($barcode_name);
	unless ($bcode) {
		$class->line->err(1);
		$class->generate_response("No such barcode in DB");
		return 1;
		}
	my $command = "perl $local_path/../scripts/QC_control.pl -b $barcode_name -v -seed $seed 2>> $logFile";
	`echo "$command" > $logFile`;
	`$command`;
	if (Atlas::parse_log("$logFile")) {
		$class->line->err(1);
		$class->generate_response("Command failed");
		return 1;
		}
	if ((defined($class->{info}->{role}))
		and(lc($class->{info}->{role}) eq 'major')) {
		if (parse_QC_log("$logFile")) {
			$bcode->QC->PASS;
			} else {
			$bcode->QC->FAIL;
			$class->line->{DB}->Claudia_say(Atlas::barcode_ident($bcode) . decode('utf8', " ДАННЫЕ ПЛОХОГО КАЧЕСТВА, НУЖНО ДО-(ПЕРЕ-)СЕКВЕНИРОВАНИЕ"));
			}
		}
	$class->generate_response("OK");
	}

sub AN {
	my $class = shift;
	
	if ($class->check_code eq 0) {
		$class->line->err(1);
		$class->generate_response("analysis code is not defined or not  found in MYSQL dictionary");
		return 1;
		}
	my $barcode_name = $class->{info}->{barcode};
	my $bcode = $class->line->{DB}->Barcode($barcode_name);
	unless($bcode) {
		$class->line->err(1);
		$class->generate_response("No such barcode");
		return 1;
		}
	if ($class->{meta}->{force_role} eq 1) {
		# Drop all major analysis if force role specified
		foreach my $Analysis ($bcode->analyses) {
			next unless defined($Analysis->info->{analysisrole});
			next unless defined($Analysis->info->{analysiscode});
			next if lc($Analysis->info->{analysiscode}) ne $class->{info}->{code};
			$Analysis->drop_major;
			}
		} elsif ((defined($class->{info}->{analysisrole}))and
			(lc($class->{info}->{analysisrole}) eq 'major')) {
			foreach my $Analysis ($bcode->analyses) {
				print "",$Analysis->info->{analysisname}," - found\n";
				next unless defined $Analysis->info->{analysisrole};
				print "HERE1\n";
				if (lc($Analysis->info->{analysisrole}) eq 'major') {
					print "HERE2\n";
					$class->line->err(1);
					$class->generate_response("can not start with major role when another major analysis exists, use -force_role option to proceed");
					return 1;
					}
				}
			}
	my $analysis = $bcode->new_analysis($class->{info});
	unless (defined($analysis)) {
		$class->line->err(1);
		$class->generate_response("Could not create such analysis");
		return 1;
		}
	my $seed = $analysis->get_id;
	my $logFile = $class->line->{DB}->config->{data_path}->{logPath} . "/analyzer/$seed.log";
	my $command = "perl $local_path/../scripts/Pipe_wrapper.pl -b $barcode_name -code ".$class->{info}->{code}." -v -seed ".$analysis->get_id." 2>> $logFile";
	`echo "$command" > $logFile`;
	`$command`;
	if (Atlas::parse_log("$logFile")) {
		$class->line->err(1);
		$class->generate_response("Command failed");
		$analysis->delete;
		return 1;
		}
	eval {$analysis->upload_data};
	if ($@) {
		$class->line->err(1);
		$class->generate_response("Command failed");
		$analysis->delete;
		return 1;
		}
	if ((defined($class->{info}->{role}))
		and(lc($class->{info}->{role}) eq 'major')) {
		$class->line->{DB}->Claudia_say(Atlas::barcode_ident($bcode) . decode('utf8', " результаты готовы"));
		}
	$class->generate_response("OK - " . $analysis->get_id);
	return ($analysis->get_id);
	}

sub UPLOAD {
	my $class = shift;
	
	my $seed = int(rand(1000000000000000000));
	
	my $logFile = $class->line->{DB}->config->{data_path}->{logPath} . "/analyzer/UPLOAD.$seed";
	my $barcode_name = $class->{info}->{barcode};
	my $analysis_name = $class->{info}->{analysis};
	my $command;
	my $Case;
	my $role = ($class->{info}->{analysisrole} || 'test');
	if (defined($analysis_name)) {
		$Case = $class->line->{DB}->Analysis($analysis_name)->Barcode->Case;
		$command = "python3 $local_path/../Claudia.python_max/claudia/upload_results.py -a $analysis_name -r $role >> $logFile 2>> $logFile";
		} elsif (defined($barcode_name)) {
		$Case = $class->line->{DB}->Barcode($barcode_name)->Case;
		$command = "python3 $local_path/../Claudia.python_max/claudia/upload_results.py -b $barcode_name -r $role >> $logFile 2>> $logFile";
		} else {
		die "Neither barcode nor analysis specified for UPLOAD"
		}
	
	#if ($class->{meta}->{force_role} eq 1) {
	#	} elsif (($role eq 'major')and
	#	((not(defined($Case->BaselineStatus)))or
	#	(not($Case->BaselineStatus->is_completed)))) {
	#		$class->line->err(1);
	#		$class->generate_response("Data upload is blocked for patient with incompleted clinical data. Use -force_role to overcome");
	#		return 1;
	#	}
	
	`echo "$command" > $logFile`;
	system("$command 2>> $logFile");
	if (Atlas::parse_log("$logFile")) {
		$class->line->err(1);
		$class->generate_response("Command failed");
		return 1;
		}
	$class->generate_response("OK");
	}

sub ANNOTATE {
	my $class = shift;

	my $seed = int(rand(1000000000000000000));
	my $logFile = $class->line->{DB}->config->{data_path}->{logPath} . "/analyzer/ANNOTATE.$seed";
	my $barcode_name = $class->{info}->{barcode};
	my $analysis_name = $class->{info}->{analysis};
	my $command;
	if (defined($analysis_name)) {
		$command = "perl $local_path/../scripts/Annotation_Wrapper.pl -a $analysis_name >> $logFile 2>> $logFile";
		} elsif (defined($barcode_name)) {
		$command = "perl $local_path/../scripts/Annotation_Wrapper.pl -b $barcode_name >> $logFile 2>> $logFile";
		} else {
		die "Neither barcode nor analysis specified for ANNOTATE"
		}
	`echo "$command" > $logFile`;
	system("$command 2>> $logFile");
	if (Atlas::parse_log("$logFile")) {
		$class->line->err(1);
		$class->generate_response("Command failed");
		return 1;
		}
	$class->generate_response("OK");
	}

sub PREPARE {
	my $class = shift;
	
	my $seed = int(rand(1000000000000000000));
	my $logFile = $class->line->{DB}->config->{data_path}->{logPath} . "/analyzer/PREPARE.$seed";
	my $barcode_name = $class->{info}->{barcode};
	my $analysis_name = $class->{info}->{analysis};
	my $command;
	if (defined($analysis_name)) {
		$command = "perl $local_path/../scripts/Prepare_Wrapper.pl -a $analysis_name >> $logFile 2>> $logFile";
		} elsif (defined($barcode_name)) {
		$command = "perl $local_path/../scripts/Prepare_Wrapper.pl -b $barcode_name >> $logFile 2>> $logFile";
		} else {
		die "Neither barcode nor analysis specified for PREPARE"
		}
	`echo "$command" > $logFile`;
	system("$command 2>> $logFile");
	if (Atlas::parse_log("$logFile")) {
		$class->line->err(1);
		$class->generate_response("Command failed");
		return 1;
		}
	$class->generate_response("OK");
	}	

sub ALL {
	my $class = shift;
	my %failed;
	
	if ($class->{info}->{code} ne 'hybrid') {
		$class->QC;
		$failed{QC} = 1 if $class->line->err;
		}

	my $analysis_name = $class->AN; 
	$failed{AN} = 1 if $class->line->err;
	
	if ($class->line->err eq 1) {
		} else {
		$class->{info}->{analysis} = $analysis_name;
		$class->ANNOTATE;
		$failed{ANNOTATE} = 1 if $class->line->err;
		}
	if ($class->line->err eq 1) {
		} else {
		if ($class->{info}->{code} ne 'hybrid') {
			$class->{info}->{analysis} = $analysis_name;
			$class->PREPARE;
			$failed{PREPARE} = 1 if $class->line->err;
			}
		}
	
	if ($class->line->err eq 1) {
		} else {
		#$class->{info}->{analysis} = $analysis_name;
		$class->UPLOAD;
		if ($class->line->err) {
			$failed{UPLOAD} = 1;
			my $barcode_name = $class->{info}->{barcode};
			my $bcode = $class->line->{DB}->Barcode($barcode_name);
			$class->line->{DB}->Claudia_say_debug(Atlas::barcode_ident($bcode) . decode('utf8', " UPLOAD failed"));
			}
		}
	my $string = [];
	foreach my $key (keys %failed) {
		push @{$string}, "$key failed";
		}
	if (scalar(@{$string}) > 0) {
		$string = join(";", @{$string});
		} else {$string = "OK: $analysis_name"}
	
	$class->generate_response("$string");
	}

sub prepare {
	my $class = shift;
	$class->parse;
	return $class;
	}

sub run {
	my $class = shift;
	unless (defined($class->{meta}->{type})) {
		$class->line->err(1);
		$class->line->response("");
		}
	my $method = $class->{meta}->{type};
	my %dic = ('QC' => 0,
			'UPLOAD' => 0,
			'AN' => 0,
			'ANNOTATE' => 0,
			'PREPARE' => 0,
			'ALL' => 0);
	unless (defined ($dic{$method})) {
		$class->line->err(1);
		$class->generate_response("Unknown command type. Use one of the following: QC, UPLOAD, AN, ANNOTATE, PREPARE");
		return 1;
		}
	
	$class->$method;
	}

sub analysis {
	my $class = shift;
	return $class->{analysis};
	}

sub generate_response {
	my $class = shift;
	my $string = shift;
	my $now = DateTime->now(time_zone => 'Europe/Moscow');
	$now = $now->strftime('%F:%H-%M-%S');
	my $response = "$now: ".$class->{cmd};
	if (defined $string) {
		$response = $response . ": " . $string;
		}
	$class->line->response($response);
	return $response;
	}

sub check_code { # Проверить что код определен и есть в словаре кодов (таблица AnalysisDic в MySQL)
	my $class = shift;
	
	my $DB = $class->line->{DB};
	my $code = $class->{info}->{code};
	return 0 unless defined $code;

	my $sth = $DB->execute("select analysisCode from AnalysisDic;");
	while (my $row = $sth->fetchrow_arrayref) {
		return 1 if lc($$row[0]) eq lc($code);
		}
	return 0;
	}
















1;
