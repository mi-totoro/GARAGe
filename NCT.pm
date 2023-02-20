package NCT;

use strict;
#use warnings;
use Dir::Self;
use lib __DIR__;
use XML::Hash;
use Fcntl qw(:flock SEEK_END);
use Moose;
use DateTime;
use feature "switch";
no if $] >= 5.018, warnings => qw( experimental::smartmatch );
use Aoddb;
use Encode;
use Data::Dumper;
use List::MoreUtils qw(uniq);
my $local_path = __DIR__ . '/';
use Data::Compare;

our @ISA = qw(Exporter);
our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub new {
	my $class	= shift;
	my $nctid	= shift;

	return undef unless defined $nctid;
	my $self = {};
	$self->{nctid} = $nctid;
	
	bless $self, $class;
	return $self;
	}

sub init {
	my $class = shift;
	$class->response;
	}

sub connect {
	my $class = shift;
	my $db = shift;
	$class->{DB} = $db;
	my $current_dir = __DIR__;
	my $configCT = $current_dir . "/..//conf/CT_GOV.json";
	$configCT = Atlas::file_to_json($configCT);
	$class->{configCT} = $configCT;
	}

sub get_id {
	my $class = shift;
	return $class->{nctid};
	}

sub adress {
	my $class = shift;
	my $id = $class->get_id;
	return "https://clinicaltrials.gov/ct2/show/$id?displayxml=true";
	}

sub response {
	my $class = shift;
	my $id = $class->get_id;

	my $cmd = "curl \"" . $class->adress."\" 2> /dev/null";
	my $response = `$cmd`;
	my $xml_converter = XML::Hash->new();
	my $xml_hash;
	my $tryNumber = 1;
	while (1) {
		return undef if $tryNumber > 100;
		eval {
			$xml_hash = $xml_converter->fromXMLStringtoHash($response);
			};
		if ($@) {
			sleep(1);
			++$tryNumber;
			} else {
			last;
			}
		}
	$class->{content} = $xml_hash;
	}

sub check_region {
	my $class = shift;
	my $region = shift;
	my $content = $class->{content};
	if (not(ref ($content->{clinical_study}->{location}) eq 'ARRAY')) {
		$content->{clinical_study}->{location} = [$content->{clinical_study}->{location}];
		}
	REGION_OUTER: foreach my $location (@{$content->{clinical_study}->{location}}) {
		if (defined($location->{status})) {
			if (defined($location->{status}->{text})) {
				next REGION_OUTER if lc($location->{status}->{text}) ne 'recruiting';
				}
			}
		next unless defined $location->{facility};
		next unless defined $location->{facility}->{address};
		next unless defined $location->{facility}->{address}->{country};
		next unless defined $location->{facility}->{address}->{country}->{text};
		my $country = lc($location->{facility}->{address}->{country}->{text});
		foreach my $key (@{$class->{configCT}->{REGION}->{$region}->{list}}) {
			next unless lc($country) eq lc($key);
			return 1;
			}
		}
	return 0;
	}

sub search_region_contacts {
	my $class = shift;
	my $region = shift;
	my $content = $class->{content};
	my $contacts;
	if ($class->check_region($region) eq 0) {
		return undef;
		}
	SRC_OUTER: foreach my $location (@{$content->{clinical_study}->{location}}) {
		if (defined($location->{status})) {
			if (defined($location->{status}->{text})) {
				next SRC_OUTER if lc($location->{status}->{text}) ne 'recruiting';
				}
			}
		next unless defined $location->{facility};
		next unless defined $location->{facility}->{address};
		next unless defined $location->{facility}->{address}->{country};
		next unless defined $location->{facility}->{address}->{country}->{text};
		my $country = lc($location->{facility}->{address}->{country}->{text});
		foreach my $key (@{$class->{configCT}->{REGION}->{$region}->{list}}) {
			goto SRC_FOUND if lc($country) eq lc($key);
			}
		next SRC_OUTER;
		SRC_FOUND:
		my $contact = $location->{contact};
		next unless defined ($contact);
		my $contact_element = parseContact($contact);
		if (defined($contact_element)) {
			push(@{$contacts}, $contact_element);
			}
		}
	return undef unless defined $contacts;
	if (scalar @{$contacts} eq 0) {return undef}
	$contacts = [sort {($a->{ContactsName} || 'zzzz') cmp ($b->{ContactsName} || 'zzzz')} @{$contacts}];
	return $contacts;
	}

sub search_city_contacts {
	my $class = shift;
	my $target_city = shift;
	my $content = $class->{content};
	my $contacts;
	SRC_OUTER: foreach my $location (@{$content->{clinical_study}->{location}}) {
		if (defined($location->{status})) {
			if (defined($location->{status}->{text})) {
				next SRC_OUTER if lc($location->{status}->{text}) ne 'recruiting';
				}
			}
		next unless defined $location->{facility};
		next unless defined $location->{facility}->{address};
		next unless defined $location->{facility}->{address}->{city};
		next unless defined $location->{facility}->{address}->{city}->{text};
		my $city = lc($location->{facility}->{address}->{city}->{text});
		next SRC_OUTER if lc($city) ne lc($target_city);
		my $contact = $location->{contact};
		next unless defined ($contact);
		my $contact_element = parseContact($contact);
		print STDERR "$contact_element\n";
		if (defined($contact_element)) {
			push(@{$contacts}, $contact_element);
			}
		}
	return undef unless defined $contacts;
	if (scalar @{$contacts} eq 0) {return undef}
	$contacts = [sort {$a->{ContactsName} cmp $b->{ContactsName}} @{$contacts}];
	return $contacts;
	}

sub contact_unique_code {
	my $contact = shift;
	my $id;
	foreach my $element_key (qw(ContactsName ContactsPhone ContactsEmail)) {
		my $element_value = 'NULL';
		if (defined($contact->{$element_key})) {
			$element_value = $contact->{$element_key}
			}
		push (@{$id}, $element_value);
		}
	return join('|', @{$id});
	}

sub drop_uniq_contacts {
	my $contacts = shift;
	my $contacts_unique;
	my $found;
	foreach my $contact (@{$contacts}) {
		my $contact_id = contact_unique_code($contact);
		next if defined($found->{$contact_id});
		$found->{$contact_id} = 1;
		push(@{$contacts_unique}, $contact);
		}
	return $contacts_unique;
	}	

sub parseContact {
	my $contact = shift;
	my $contact_element;
	if (defined($contact->{last_name}->{text})) {
		$contact_element->{ContactsName} = $contact->{last_name}->{text}
		}
	if (defined($contact->{email}->{text})) {
		$contact_element->{ContactsEmail} = $contact->{email}->{text}
		}
	if (defined($contact->{phone}->{text})) {
		$contact_element->{ContactsPhone} = $contact->{phone}->{text}
		}
	if (scalar(keys %{$contact_element}) > 0) {
		return $contact_element;
		} else {
		return undef;
		}
	}	

sub getContacts {
	my $class = shift;
	my $content = $class->{content};
	my $contacts;
	if (defined($class->search_city_contacts('Moscow'))) {
		$contacts = $class->search_city_contacts('Moscow');
		} elsif (defined($class->search_region_contacts('USA'))) {
			$contacts = $class->search_region_contacts('USA');
			}
	my $overall_contact = $content->{clinical_study}->{overall_contact};
	if (defined($overall_contact)) {
		my $contact_element = parseContact($overall_contact);
		if (defined($contact_element)) {
			push(@{$contacts}, $contact_element);
			}
		}
	$contacts = drop_uniq_contacts($contacts);
	$contacts = [@{$contacts}[0..($class->{configCT}->{CONTACT_LIMIT} - 1)]];
	return $contacts;
	}

sub locate {
	my $class = shift;
	my $NCTid = $class->get_id;
	
	my $result;
	my $study = $class->{content};
	$result->{CTID} = $NCTid;
	$result->{CTName} = "N/A";
	$result->{CTName} = $study->{clinical_study}->{brief_title}->{text};
	$result->{CTName} =~ s/'//;
	foreach my $region (sort {$class->{configCT}->{REGION}->{$a}->{text_ru} cmp $class->{configCT}->{REGION}->{$b}->{text_ru}} keys %{$class->{configCT}->{REGION}}) {
		next if ($class->{configCT}->{REGION}->{$region}->{used}) eq 0;
		my $data = {};
		$data->{"CTLocName"} = $class->{configCT}->{REGION}->{$region}->{text_ru};
		$data->{"CTCond"} = $class->check_region($region);
		push(@{$result->{CTLoc}}, $data);
		}
	$result->{DrugList} = [];
	if (defined($study->{clinical_study}->{study_design_info}->{allocation}->{text})) {
		push (@{$result->{DrugList}}, {"CTDrug" => translate_CTDrug($study->{clinical_study}->{study_design_info}->{allocation}->{text})}) unless ($study->{clinical_study}->{study_design_info}->{allocation}->{text})eq 'N/A';
		}
	if (defined($study->{clinical_study}->{phase}->{text})) {
		push (@{$result->{DrugList}}, {"CTDrug" => translate_CTDrug($study->{clinical_study}->{phase}->{text})});
		}
	$result->{CTContacts} = $class->getContacts;
	$result = Atlas::json_to_data($result);
	return $result;
	}

sub translate_CTDrug {
	my $input = shift;
	$input =~ s/Phase/Фаза/g;
	$input =~ s/phase/фаза/g;
	$input =~ s/Non-Randomized/Нерандомизированное/g;
	$input =~ s/Randomized/Рандомизированное/g;
	return $input;
	}

sub getArmDescription {
	my $arm = shift;
	my $description = '';
	if (defined($arm->{description})) {
		if (defined($arm->{description}->{text})) {
			$description = $arm->{description}->{text};
			}
		}
	return $description;
	}	

sub getherArms {
	my $class = shift;
	my $content = $class->{content};
	my $result;
	if (ref $content->{clinical_study}->{arm_group} eq 'ARRAY') {
		foreach my $arm (@{$content->{clinical_study}->{arm_group}}) {
			$result->{$arm->{arm_group_label}->{text}} = getArmDescription($arm);
			}
		} elsif (ref $content->{clinical_study}->{arm_group} eq 'HASH') {
		my $arm = $content->{clinical_study}->{arm_group};
		$result->{$arm->{arm_group_label}->{text}} = getArmDescription($arm);
		}
	return $result;
	}

sub getInterventionArmLabel {
	my $intervention = shift;
	my $arm_label = [];
	if (defined($intervention->{arm_group_label})) {
		if (ref $intervention->{arm_group_label} eq 'ARRAY') {
			foreach my $arm (@{$intervention->{arm_group_label}}) {
				push @{$arm_label}, $arm->{text};
				}
			} else {
			if (defined($intervention->{arm_group_label}->{text})) {
				push @{$arm_label}, $intervention->{arm_group_label}->{text};
				}
			}
		}
	return $arm_label;
	}

sub filterDrugName {
	my $text = shift;
	return 0 if lc($text) =~ /cytology/;
	return 0 if lc($text) =~ /collection/;
	return 0 if lc($text) =~ /surgery/;
	return 0 if lc($text) =~ /resection/;
	return 0 if lc($text) =~ /collection/;
	return 0 if lc($text) =~ /biomarker/;
	return 1;
	}	

sub getherInterventions {
	my $class = shift;
	my $content = $class->{content};
	my $result;
	if (ref $content->{clinical_study}->{arm_group} eq 'ARRAY') {
		$content->{clinical_study}->{intervention} = [$content->{clinical_study}->{intervention}] unless (ref $content->{clinical_study}->{intervention}) eq 'ARRAY';
		foreach my $intervention (@{$content->{clinical_study}->{intervention}}) {
			my $name;
			if (defined($intervention->{intervention_name})) {
				$name = $intervention->{intervention_name}->{text};
				}
			next unless defined $name;
			next unless filterDrugName($name);
			$result->{$name} = getInterventionArmLabel($intervention);
			}
		} elsif (ref $content->{clinical_study}->{arm_group} eq 'HASH') {
		my $name;
		$content->{clinical_study}->{intervention} = [$content->{clinical_study}->{intervention}] unless (ref $content->{clinical_study}->{intervention}) eq 'ARRAY';
		foreach my $intervention (@{$content->{clinical_study}->{intervention}}) {
			my $name;
			if (defined($intervention->{intervention_name})) {
				$name = $intervention->{intervention_name}->{text};
				}
			return undef unless defined $name;
			return undef unless filterDrugName($name);
			$result->{$name} = getInterventionArmLabel($intervention);
			}
		}
	return $result;
	}

sub checkArm {
	my $text = shift;
	my $biomarker = shift;
	if ($text =~ /$biomarker/) {
		return 1;
		} else {
		return 0;
		}
	}

sub getDrugList {
	my $class = shift;
	my $content = $class->{content};
	my $biomarker = shift;
	my $armDescr  = $class->getherArms;
	my $drugArms = $class->getherInterventions;
	my $result = {};
	$result->{"-COMMON-"} = [];
	foreach my $armArray (values %{$drugArms}) {
		foreach my $arm (@{$armArray}) {
			$result->{$arm} = [];
			}
		}
	if (defined($drugArms)) {
		foreach my $Drug (keys %{$drugArms}) {
			if (defined($biomarker)) {
				foreach my $drugArm (@{$drugArms->{$Drug}}) {
					if ((defined($drugArm))and(length($drugArm) > 0)) {
						my $arm_name = $drugArm;
						if (defined($armDescr->{$drugArm})) {
							if ((checkArm($drugArm, $biomarker))
								or(checkArm($armDescr->{$drugArm}, $biomarker))) {
								push (@{$result->{$arm_name}}, $Drug);
								} else {
								#push (@{$result->{"-COMMON-"}}, $Drug);
								}
							} else {
							push (@{$result->{"-COMMON-"}}, $Drug);
							}
						} else {
						push (@{$result->{"-COMMON-"}}, $Drug);
						}
					}
				} else {
				push (@{$result->{"-COMMON-"}}, $Drug);
				}
			}
		}
	my $final;
	#print STDERR Dumper $result;
	foreach my $arm (keys %{$result}) {
		my $drugList = $result->{$arm};
		$drugList = drugPretty($drugList);
		$drugList = $class->selectKnownDrugs($drugList);
		next if scalar @{$drugList} eq 0;
		my $isAdded = 0;
		foreach my $armAdded (keys %{$final}) {
			my $C = Data::Compare->new($final->{$armAdded}, $drugList);
			if ($C->Cmp) {
				$isAdded = 1;
				last;
				}
			}
		$final->{$arm} = $drugList if $isAdded eq 0;
		}
	#print STDERR Dumper $final;
	if ((scalar(keys %{$final}) > 1)and(defined($final->{"-COMMON-"}))) {
		delete $final->{"-COMMON-"};
		}
	return $final;
	}

sub drugPretty { # returns array ref
	my $drugs = shift; # ref to array
	my @result;
	foreach my $drug (@{$drugs}) {
		my @mas = split/plus/, $drug;
		map {$_ =~ s/^\s+|\s+$//g} @mas;
		map {push(@result, $_)} @mas;
		}
	return [(uniq @result)];
	}	

sub selectKnownDrugs { # returns array ref
	my $class = shift;
	my $drugs = shift; # ref to array
	my @result;
	foreach my $drug (@{$drugs}) {
		my @found = $class->{DB}->searchDrugInString($drug);
		map {$_ = $class->{DB}->Drug($_)->info->{"activesubstancename"}} @found;
		push (@result, @found);
		}
	return [(uniq @result)];
	}

sub drugList { # RETURN ref to hash, where keys - arms and values - known in database drug names (in english). Common arm name is '-COMMON-'
	my $class = shift;
	my $NCTid = $class->get_id;
	my $biomarker = shift;
	my $study = $class->{content};
	my $result;
	
	if (defined($biomarker)) {
		$result = $class->getDrugList($biomarker);
		if (scalar (keys %{$result}) eq 0) {
			$result = $class->getDrugList(undef);
			}
		} else {
		$result = $class->getDrugList(undef);
		}
	my @array;
	foreach my $key (keys %{$result}) {
		push (@array, $result->{$key});
		}
	return \@array;
	}





































1;
