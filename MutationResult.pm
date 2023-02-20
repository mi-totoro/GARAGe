package Table::MutationResult;

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
my $local_path = __DIR__ . '/';

has tablename	=> 'MutationResult';
has id_field	=> 'mutationresultid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub Analysis {
	my $class = shift;
	my $analysis_name = $class->info->{analysisname};
	return undef unless defined $analysis_name;
	return $class->{DB}->Analysis($analysis_name);
	}

sub Mutation {
	my $class = shift;
	return $class->{DB}->Mutation($class->info->{mutationid});	
	}

sub variantDescription {
	my $class = shift;
	my $result;
	my @parts;
	my $MT = $class->Mutation->name.":germline_het";
	$MT = Table::MolecularTarget->fetch($class->{DB}, $MT);
	my $med_gene;
	if (defined($MT)) {
		$med_gene = $MT->gether_phenotype_text;
		}

	my $dGene = $class->Mutation->VariantAnnotation->Transcript->Gene->geneDescription_biology_select($class->Analysis->Barcode->Case->ClinicalInterpretation->info->{pathologycodepurpose});
	my $pVar = $class->RTP_description;chomp $pVar if defined $pVar;

	my $description = ($dGene ? $dGene->{"desc"} : undef);
	
	my $ACMG_validation_text = encode('utf-8', 'В соответствии с рекомендациями ACMG (Richards et al., 2015) рекомендована валидация варианта на образце нормальной ткани референсным методом секвенирования по Сэнгеру. Правильно оценить прогноз болезни, составить программу индвидуального скрининга, а также узнать риски наследственных форм онкологии у родственников поможет врач-генетик. Мы рекомендуем записаться на консультацию.');
	if (defined($med_gene)) {
		push (@parts, $class->variantDescription_common);
		push (@parts, $description) if defined($description);
		push (@parts, $med_gene) if defined($med_gene);
		push (@parts, $pVar) if defined($pVar);
		push (@parts, $ACMG_validation_text) if defined($med_gene);
		} else {
		push (@parts, $class->variantDescription_common);
		push (@parts, $description) if defined($description);
		push (@parts, $pVar) if defined($pVar);
		push (@parts, $med_gene) if defined($med_gene);
		}
	return join("\n", @parts);
	}

sub RTP_description {
	my $class = shift;
	my $result = undef;
	
	my $response = "python $local_path/../../scripts/python/SS_variant_RTP_desc.py '" . 
		($class->Analysis->Barcode->Case->InternalBarcode->info->{'internalbarcodeid'}) . 
		"' '" . ($class->Mutation->name) . "'";
	$response = Atlas::wrap_python($response);
	return undef if length($response) < 2;
	return $response;
	}

sub variantDescription_common { # Подготовить описание варианта для вывода в отчет
	my $class = shift;
	my $result;
	my @sentences;
	my $sentence;

	my $Mutation = $class->Mutation;
	my $VariantAnnotation = $Mutation->VariantAnnotation;
	return "" unless defined $VariantAnnotation;
	my $Transcript = $VariantAnnotation->Transcript;
	return "" unless defined $Transcript;
	my $Gene = $Transcript->Gene;
	return "" unless defined $Gene;

	########## Sentence
	$sentence = "";
	my $effect;
	$effect = $VariantAnnotation->info->{hgvsp};
	if ((defined($effect))and($effect eq '')) {$effect = undef}
	if (defined($effect)) {
		$effect = "p.$effect";
		} else {
		$effect = $VariantAnnotation->info->{hgvsc};
		if (defined($effect)) {
			$effect = "c.$effect";
			}
		}
	if (defined($effect)) {
		$effect = "$effect (".$Transcript->get_id.")";
		} else {
		$effect = $Mutation->name;
		}
	my $VAF = $class->info->{allelefrequency};
	if ($VAF > 0.05) {
		$VAF = int(100*$VAF);
		} else {
		$VAF = int(1000*$VAF)/10;
		}
	$sentence = "В образце обнаружен вариант гена ".$Gene->info->{genesymbol}." $effect";
	$sentence = "$sentence с частотой альтернативного аллеля $VAF%";
	push(@sentences, $sentence);
	$sentence = '';
	#####
	# ONE SENTENCE FOR EACH VARIANT EFFECT
	foreach my $Consequence ($VariantAnnotation->consequences) {
		if ($Consequence->info->{variantconsequence} eq 'missense_variant') {
			$sentence = "Вариант приводит к замене единичной аминокислоты в первичной последовательности белка (миссенс вариант)";
			}
		if ($Consequence->info->{variantconsequence} eq 'stop_gained') {
			$sentence = "Вариант приводит к образованию стоп-кодона и преждевременной терминации трансляции белка (нонсенс вариант)";
			}
		if ($Consequence->info->{variantconsequence} eq 'inframe_deletion') {
			my $aaref = $VariantAnnotation->info->{aaref};
			my $aaalt = $VariantAnnotation->info->{aaalt};
			$aaref =~ s/-//;
			$aaalt =~ s/-//;
			my $lengthDiff = length($aaref) - length($aaalt);
			print STDERR $VariantAnnotation->info->{aaref},"\n";
			print STDERR $VariantAnnotation->info->{aaalt},"\n";
			my $aaWord = pluralForm($lengthDiff, 'аминокислоты', 'аминокислот', 'аминокислот');
			$lengthDiff = translatePlural($lengthDiff, 'f');
			$sentence = "Вариант приводит к делеции $lengthDiff $aaWord в первичной последовательности белка без изменения рамки чтения гена";
			}
		if ($Consequence->info->{variantconsequence} eq 'inframe_insertion') {
			my $lengthDiff = length($VariantAnnotation->info->{aaalt}) - length($VariantAnnotation->info->{aaref});
			my $aaWord = pluralForm($lengthDiff, 'аминокислоты', 'аминокислот', 'аминокислот');
			$lengthDiff = translatePlural($lengthDiff, 'f');
			$sentence = "Вариант приводит к вставке $lengthDiff $aaWord в первичной последовательности белка без изменения рамки чтения гена";
			}
		if ($Consequence->info->{variantconsequence} eq 'splice_acceptor_variant') {
			$sentence = "Вариант расположен на экзон/интронной границе и может приводить к некорректному сплайсингу мРНК (вариант сайта сплайсинга)";
			}
		if ($Consequence->info->{variantconsequence} eq 'splice_donor_variant') {
			$sentence = "Вариант расположен на экзон/интронной границе и может приводить к некорректному сплайсингу мРНК (вариант сайта сплайсинга)";
			}
		if ($Consequence->info->{variantconsequence} eq 'splice_region_variant') {
			$sentence = "Вариант расположен на экзон/интронной границе и может приводить к некорректному сплайсингу мРНК (вариант сайта сплайсинга)";
			}
		if ($Consequence->info->{variantconsequence} eq 'frameshift_variant') {
			my $effect;
			my $ref = $Mutation->info->{mutationref};
			my $alt = $Mutation->info->{mutationalt};
			my $count;
			if (length($ref) > length($alt)) {
				$effect	= "делеции";
				$count	= (length($ref) - length($alt));
				} else {
				$effect	= "вставке";
				$count	= (length($alt) - length($ref));
				}
			my $nWord = pluralForm($count, 'нуклеотида', 'нуклеотидов', 'нуклеотидов');
			$count = translatePlural($count, 'm');
			$sentence = "Вариант приводит к $effect $count $nWord в последовательности ДНК и сдвигу рамки считывания гена, что влечет изменение первичной последовательности белка, следующей после сайта варианта";
			if ((defined($VariantAnnotation->info->{hgvsp}))and(lc($VariantAnnotation->info->{hgvsp}) =~ /ter/)) {
				$sentence = "$sentence и образованию преждевременного стоп-кодона";
				}
			}
		push (@sentences, $sentence);
		}
	$sentence = '';
	#####
	# dbSNP annotation
	if (defined($Mutation->info->{mutationrs})) {
		$sentence = "Вариант описан в базе наследственных генетических вариантов dbSNP (".$Mutation->info->{mutationrs}.")";
		} else {
		$sentence = "Вариант не описан в базе наследственных генетических вариантов dbSNP";
		}
	push (@sentences, $sentence);
	$sentence = '';
	#####
	# population Frequency
	my $PopulationFrequency = $Mutation->PopulationFrequency;
	if (defined($PopulationFrequency)) {
		my $project = Table::PopulationProjectDic->fetch($class->{DB}, $PopulationFrequency->info->{projectcode})->info->{projectname_r};
		my $frequency = $PopulationFrequency->info->{freq};
		$frequency = 100*$frequency;
		$sentence = "Частота выявленного варианта в общей популяции в соответствии с $project составляет $frequency%";
		} else {
		$sentence = "Вариант не встречается в общей популяции в соответствии с результатами проектов TOPMED/1000 Геномов/ExAC";
		}
	push (@sentences, $sentence);
	$sentence = '';
	#####
	# COSMIC annotation
	my $mgtType = $class->Analysis->Barcode->Case->info->{mgttypecode};
	if ((defined($mgtType))and(lc($mgtType) =~ 'germline')) {
		
		} else {
		my $cosmic = $Mutation->info->{mutationcosmic};
		if (defined($cosmic)) {
			$sentence = "Вариант описан в базе данных соматических мутаций COSMIC ($cosmic)";
			} else {
			$sentence = "Вариант не описан в базе данных соматических мутаций COSMIC";
			}
		push (@sentences, $sentence);
		}
	#####
	# Variant Origin Prediction Result
	if (defined($mgtType)and(lc($mgtType) =~ 'germline')) {
		$sentence = "В соответствии с методологией эксперимента вариант является наследственным";
		} else {
		my $origin = $class->info->{zygositycurated};
		if (defined($origin)) {
			if ($origin eq 'somatic') {
				$sentence = "На основании имеющейся информации вариант вероятно является соматическим";
				}
			if ($origin eq 'germline_het') {
				$sentence = "На основании имеющейся информации вариант вероятно является наследственным (гетерозиготный вариант)";
				}
			if ($origin eq 'germline_hom') {
				$sentence = "На основании имеющейся информации вариант вероятно является наследственным (гомозиготный вариант)";
				}
			if ($origin eq 'germline_nos') {
				$sentence = "На основании имеющейся информации вариант вероятно является наследственным";
				}
			if ($origin eq 'variant_nos') {
				$sentence = "На основании имеющейся информации нельзя достоверно свидетельствовать о происхождении варианта (соматический или наследственный)";
				}
			}
		}
	push(@sentences, $sentence);
	
	$result = join(". ", @sentences).".";
	return encode('UTF-8', $result);
	}

sub translatePlural {
	my $n = shift;
	my $sex = shift; # f/m
	if ($sex eq 'f') {
		return 'одной' if $n eq 1;
		} else {
		return 'одного' if $n eq 1;
		}
	return 'двух' if $n eq 2;
	return 'трех' if $n eq 3;
	return 'четырех' if $n eq 4;
	return 'пяти' if $n eq 5;
	return $n;
	}	

sub pluralForm {
	my $n = shift;
	my $form1 = shift; # именительный падеж, ед. число: одного ...
	my $form2 = shift; # родительный падеж, мн. число: двух ...
	my $form5 = shift; # родительный падеж, мн. число: пяти ...
	$n = abs($n) % 100;
	my $n1 = $n % 10;
	if (($n > 10) and ($n < 20)) {return $form5};
	if (($n1 > 1) and ($n1 < 5)) {return $form2};
	if ($n1 eq 1) {return $form1};
	return $form5;
	}

sub is_signCT { # is significant for RecommendationCT
	my $class = shift;
	
	foreach my $RCT ($class->Analysis->Barcode->Case->ClinicalInterpretation->RCTs) {
		next unless (defined($RCT->info->{moleculartargetid}));
		my $MT = Table::MolecularTarget->fetch($class->{DB}, $RCT->info->{moleculartargetid});
		my $name = lc($class->Mutation->name);
		return 1 if lc($MT->json) =~ /$name:/;
		}
	return 0;
	}

sub is_signTP { # is significant for RecommendationTP
	my $class = shift;
	foreach my $RTP ($class->Analysis->Barcode->Case->ClinicalInterpretation->RTPs) {
		next unless (defined($RTP->info->{moleculartargetid}));
		my $MT = Table::MolecularTarget->fetch($class->{DB}, $RTP->info->{moleculartargetid});
		my $name = lc($class->Mutation->name);
		my $count = 1;
		$count = 2 if $RTP->info->{confidencelevel} eq '1';
		$count = 2 if lc($RTP->info->{confidencelevel}) eq '2a';
		$count = 2 if lc($RTP->info->{confidencelevel}) eq '2b';
		$count = 2 if lc($RTP->info->{confidencelevel}) eq 'r1';
		return $count if lc($MT->json) =~ /$name:/;
		}
	return 0;
	}

sub is_signGC { # is significant for RecommendationGC
	my $class = shift;
	foreach my $RGC ($class->Analysis->Barcode->Case->ClinicalInterpretation->RGCs) {
		next unless (defined($RGC->info->{moleculartargetid}));
		my $MT = Table::MolecularTarget->fetch($class->{DB}, $RGC->info->{moleculartargetid});
		my $name = lc($class->Mutation->name);
		return 2 if lc($MT->json) =~ /$name:/;
		}
	return 0;
	}

sub toBeReported {
	my $class = shift;
	return 0 unless defined $class->info->{zygositycurated};
	return 0 if (lc($class->info->{zygositycurated}) =~ /wt/);
	return 1 if lc($class->info->{zygositycurated}) eq 'somatic';
	return 1 if lc($class->info->{zygositycurated}) eq 'variant_nos';
	return 1 if $class->is_signTP;
	return 1 if $class->is_signGC;
	return 1 if $class->is_signCT;
	if (lc($class->info->{zygositycurated}) eq 'germline_het') {
		my $MT = Table::MolecularTarget->fetch($class->{DB}, $class->Mutation->name.":germline_het");
		return 0 unless defined $MT;
		foreach my $VI ($MT->variantInterpretations) {
			return 1 if lc($VI->info->{interpretationresult}) eq 'pathogenic';
			return 1 if lc($VI->info->{interpretationresult}) eq 'likely pathogenic';
			return 1 if lc($VI->info->{interpretationresult}) eq 'vus';
			}
		}
	return 0;
	}

sub annotate_from_vcf {
	my $class = shift;
	my $field = shift;

	my $vcf = $class->Analysis->vcf;
	return undef unless defined $vcf;
	open (my $afv, "<".$vcf->path);
	my $Mutation = $class->Mutation;
	while (<$afv>) {
		chomp;
		next if m!#!;
		my @mas = split/\t/;
		next unless $mas[0] eq $Mutation->info->{mutationchr};
		next unless $mas[1] eq $Mutation->info->{mutationgenomicpos};
		next unless $mas[3] eq $Mutation->info->{mutationref};
		next unless $mas[4] eq $Mutation->info->{mutationalt};
		my @info = split/;/, $mas[7];
		foreach my $arg (@info) {
			if ($arg =~ /^$field=(\S+)$/) {
				return $1;
				}
			}
		}
	close $afv;
	return undef;
	}



























1;
