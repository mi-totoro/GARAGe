package Table::MolecularTarget;

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
use Text::Balanced qw(extract_multiple extract_bracketed);
use Data::Compare;
use List::MoreUtils qw(uniq);

has tablename	=> 'MolecularTarget';
has id_field	=> 'moleculartargetid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub json {
	my $class = shift;
	
	my $result;
	if (defined($class->info->{parenttype})) {
		my @names;
		my $sql_cmd = "SELECT molecularTargetId FROM MolecularTarget where molecularTargetParent = '".$class->get_id."'";
		my $sth = $class->{DB}->execute($sql_cmd);
		while (my $row = $sth->fetchrow_arrayref) {
			push @names, Table::MolecularTarget->fetch($class->{DB}, $$row[0])->json;
			}
		if (uc($class->info->{parenttype}) eq 'AND') {
			$result = "{'AND':[" . join(",", @names) . "]}";
			}
		if (uc($class->info->{parenttype}) eq 'OR') {
			$result = "{'OR':[" . join(",", @names) . "]}";
			}
		} else {
		my @names;
		foreach my $MutationRule ($class->mutationRules) {
			push @names, "['".$MutationRule->name."']";
			}
		foreach my $CNV ($class->CNVs) {
			push @names, "['".$CNV->name."']";
			}
		if (scalar(@names) eq 1) {
			$result = $names[0];
			} else {
			$result = "{'AND':[" . join(",", @names) . "]}";
			}
		}
	$result =~ s/'/"/g;
	return lc($result);
	}

sub mutationRules {
	my $class = shift;
	
	my $sql_cmd = "SELECT MolecularTargetBuilder.mutationRuleId FROM MolecularTargetBuilder INNER JOIN MutationRule ON MolecularTargetBuilder.mutationRuleId = MutationRule.mutationRuleId WHERE molecularTargetId = '".$class->get_id."' ORDER BY MutationRule.mutationId;";
	my $sth = $class->{DB}->execute($sql_cmd);
	my @mutationRules;
	while (my $row = $sth->fetchrow_arrayref) {
		my $MutationRule = Table::MutationRule->fetch($class->{DB}, $$row[0]);
		push (@mutationRules, $MutationRule);
		}
	return @mutationRules;
	}

sub CNVs {
	my $class = shift;
	
	my $sql_cmd = "SELECT MolecularTargetBuilder.CNVId FROM MolecularTargetBuilder INNER JOIN CNV ON MolecularTargetBuilder.CNVId = CNV.CNVId WHERE molecularTargetId = '".$class->get_id."' ORDER BY CNV.CNVId;";
	my $sth = $class->{DB}->execute($sql_cmd);
	my @CNVs;
	while (my $row = $sth->fetchrow_arrayref) {
		my $CNV = Table::CNV->fetch($class->{DB}, $$row[0]);
		push (@CNVs, $CNV);
		}
	return @CNVs;
	}

sub fetch {
	my $class = shift;
	my $DB = shift;
	my $id = shift;
	
	$id = lc($id);
	my $self = $class->new;
	$self->connect($DB);
	if ($id =~ /^(\d+)$/) {
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
		} elsif (Atlas::isVariantRuleFormat(decode_id($id))) {
		my $input = decode_id($id);
		my $MutationRule = Table::MutationRule->fetch($DB, $input);
		return undef unless defined $MutationRule;
		my $sql_cmd = "select molecularTargetId from MolecularTargetBuilder where mutationRuleId = ".$MutationRule->get_id.";";
		my $sth = $DB->execute($sql_cmd);
		my $counter = 0;
		while (my $row = $sth->fetchrow_arrayref) {
			++$counter;
			$input = $$row[0];
			my $MT = Table::MolecularTarget->fetch($DB, $input);
			next if defined($MT->info->{parenttype});
			next if defined($MT->info->{molecularTargetParent});
			}
		} elsif (Atlas::isCNVFormat(decode_id($id))) {
		my $input = decode_id($id);
		my $CNV = Table::CNV->fetch($DB, $input);
		return undef unless defined $CNV;
		my $sql_cmd = "select molecularTargetId from MolecularTargetBuilder where CNVId = ".$CNV->get_id.";";
		my $sth = $DB->execute($sql_cmd);
		my $counter = 0;
		while (my $row = $sth->fetchrow_arrayref) {
			++$counter;
			$input = $$row[0];
			my $MT = Table::MolecularTarget->fetch($DB, $input);
			next if defined($MT->info->{parenttype});
			next if defined($MT->info->{molecularTargetParent});
			}
		}
	if ($id =~ /;/) {
		$id = [split/;/, $id];
		map {$_ = "['$_']"} @{$id};
		$id = "{'and':[".join(',', @{$id})."]}";
		$id =~ s/'/"/g;
		} else {
		if (($id !~ /^\[/)and($id !~ /^'/)and($id !~ /^{/)) {
			$id = "['$id']";
			}
		$id =~ s/'/"/g;
		}
	my $reference = Atlas::data_to_json($id);
	foreach my $MolecularTarget ($DB->molecularTargets) {
		#next if $MolecularTarget->get_id ne 7934;
		my $current = Atlas::data_to_json($MolecularTarget->json);
		#print STDERR Dumper $current;
		#print STDERR Atlas::json_to_data($reference),"\n";
		#print STDERR Atlas::json_to_data($current),"\n";
		if (Atlas::struct_compare($reference, $current)) {
			#print STDERR "<-This\n";
			return $MolecularTarget;
			}
		}
	return undef;
	}

sub decode_id {
	my $string = shift;
	if ($string =~ /^\'?\(?\{?\[?(\S+:\d+[AGCTNagctn]+>[AGCTNagctn]+:\w+)\}?\]?\)?\'?$/) {
		return $1;
		}
	if ($string =~ /^\'?\(?\{?\[?(\S+:del)\}?\]?\)?\'?$/) {
		return $1;
		}
	if ($string =~ /^\'?\(?\{?\[?(\S+:amp)\}?\]?\)?\'?$/) {
		return $1;
		}
	return $string;
	}

sub encode_id {
	my $string = shift;
	if (($string !~ /^\[/)and($string !~ /^'/)and($string !~ /^{/)) {
		$string = "['$string']";
		}
	$string =~ s/'/"/g;
	return $string;
	}

sub forceFetch {
	my $class	= shift;
	my $DB		= shift;
	my $name	= shift;
	my $self = $class->fetch($DB, $name);
	if (defined($self)) {
		return $self;
		} else {
		if ($name =~ /^\'?\(?\{?\[?([^:;>]+):(\d+)([AGCTNagctn]+)>([AGCTNagctn]+):(\w+)\}?\]?\)?\'?$/) {
			my $chr = $1;
			my $pos = $2;
			my $ref = $3;
			my $alt = $4;
			my $zyg = $5;
			my $MutationRule = Table::MutationRule->forceFetch($DB, "$chr:$pos$ref>$alt:$zyg");
			return undef unless defined $MutationRule;
			my $info;
			my $hgvs = $MutationRule->Mutation->VariantAnnotation->info->{hgvsp};
			$hgvs = $MutationRule->Mutation->VariantAnnotation->info->{hgvsc} unless defined $hgvs;
			$info->{moleculartargetnote} = $MutationRule->Mutation->VariantAnnotation->Transcript->Gene->info->{'genesymbol'}." $hgvs";
			$info->{moleculartargetcode} = "single ".$MutationRule->name;
			my $id = Table::MolecularTarget->insert_row($DB, $info);
			my $MolecularTarget = Table::MolecularTarget->fetch($DB, $id);
			$MolecularTarget->associateMutationRule($MutationRule);
			return $MolecularTarget;
			} elsif ($name =~ /^\'?\(?\{?\[?(\S+):(amp|del)\}?\]?\)?\'?$/) {
			my $gene_symbol = $1;
			my $type = $2;
			my $CNV = Table::CNV->fetch($DB, "$gene_symbol:$type");
			return undef unless defined $CNV;
			my $info;
			my $type_full = 'deletion';
			$type_full = 'amplification' if $type eq 'amp';
			$info->{moleculartargetnote} = "$gene_symbol $type_full";
			$info->{moleculartargetcode} = "single ".$CNV->name;
			my $id = Table::MolecularTarget->insert_row($DB, $info);
			my $MolecularTarget = Table::MolecularTarget->fetch($DB, $id);
			$MolecularTarget->associateCNV($CNV);
			return $MolecularTarget;
			} else {
			my @var_input = split/;/, $name;
			my @MR_output;
			my @CNV_output;
			my @genes;
			my @genes_deleted;
			my @genes_amplified;
			foreach my $var (@var_input) {
				if ($var =~ /^\'?\(?\{?\[?([^:;>]+):(\d+)([AGCTNagctn]+)>([AGCTNagctn]+):(\w+)\}?\]?\)?\'?$/) {
					my $MutationRule = Table::MutationRule->forceFetch($DB, "$1:$2$3>$4:$5");
					return undef unless defined $MutationRule;
					push @genes, $MutationRule->Mutation->VariantAnnotation->Transcript->Gene->info->{'genesymbol'};
					push @MR_output, $MutationRule;
					} elsif ($var =~ /^\'?\(?\{?\[?(\S+):(amp|del)\}?\]?\)?\'?$/) {
					my $type = $2;
					my $CNV = Table::CNV->fetch($DB, "$1:$2");
					return undef unless defined $CNV;
					push @genes_amplified, $CNV->Gene->info->{'genesymbol'} if $type eq 'amp';
					push @genes_deleted, $CNV->Gene->info->{'genesymbol'} if $type eq 'del';
					push @CNV_output, $CNV;
					} else {
					return undef;
					}
				}
			@genes = uniq @genes;
			my $info;
			my @codes;
			push @codes, "mutation ". $genes[0] if scalar @genes eq 1;
			push @codes, "co-mutation ". join(',', sort {$a cmp $b} @genes) if scalar @genes > 1;

			push @codes, "amplification ". $genes_amplified[0] if scalar @genes_amplified eq 1;
			push @codes, "co-amplification ". join(',', sort {$a cmp $b} @genes_amplified) if scalar @genes_amplified > 1;

			push @codes, "deletion ". $genes_deleted[0] if scalar @genes_deleted eq 1;
			push @codes, "co-deletion ". join(',', sort {$a cmp $b} @genes_deleted) if scalar @genes_deleted > 1;

			$info->{moleculartargetcode} = join(', ', @codes);
			my $id = Table::MolecularTarget->insert_row($DB, $info);
			my $MT = Table::MolecularTarget->fetch($DB, $id);
			foreach my $MR (@MR_output) {
				$MT->associateMutationRule($MR);
				}
			foreach my $CNV (@CNV_output) {
				$MT->associateCNV($CNV);
				}
			return $MT;
			}
		}
	}

sub isPositive {
	my $class	= shift;
	my $Case	= shift;
	my $ResultStructure	= shift;
	
	unless (defined($ResultStructure)) {
		foreach my $Barcode ($Case->barcodes) {
			my $Analysis = $Barcode->major_AN;
			next unless defined $Analysis;
			$ResultStructure->{MutationResult}->{$Analysis->get_id} = [$Analysis->mutationResults];
			}
		}

	my $result;
	if (defined($class->info->{parenttype})) {
		my $sql_cmd = "SELECT molecularTargetId FROM MolecularTarget where molecularTargetParent = '".$class->get_id."'";
		my $sth = $class->{DB}->execute($sql_cmd);
		my @children;
		while (my $row = $sth->fetchrow_arrayref) {
			push @children, Table::MolecularTarget->fetch($class->{DB}, $$row[0]);
			}
		if (uc($class->info->{parenttype}) eq 'AND') {
			my $result = 1;
			foreach my $MolecularTarget(@children) {
				$result = 0 if ($MolecularTarget->isPositive($Case, $ResultStructure) eq 0);
				}
			return $result;
			}
		if (uc($class->info->{parenttype}) eq 'OR') {
			my $result = 0;
			foreach my $MolecularTarget(@children) {
				$result = 1 if ($MolecularTarget->isPositive($Case, $ResultStructure) eq 1);
				}
			return $result;
			}
		} else {
		$result = 1;
		foreach my $MutationRule ($class->mutationRules) {
			my $resultLocal;
			if (defined($ResultStructure->{MutationRule}->{$MutationRule->get_id})) {
				$resultLocal = $ResultStructure->{MutationRule}->{$MutationRule->get_id};
				} else {
				$resultLocal = $MutationRule->isPositive($Case, $ResultStructure);
				$ResultStructure->{MutationRule}->{$MutationRule->get_id} = $resultLocal;
				}
			$result = 0 if $resultLocal eq 0;
			}
		return $result;
		}
	return undef;
	}

sub associateMutationRule {
	my $class = shift;
	my $MutationRule = shift;

	my $sql_cmd = "INSERT INTO `MolecularTargetBuilder` (molecularTargetId, mutationRuleId) VALUES ('".$class->get_id."', '".$MutationRule->get_id."');";
	my $sth = $class->{DB}->execute($sql_cmd);
	return 0;
	}

sub associateCNV {
	my $class = shift;
	my $CNV = shift;
	
	my $sql_cmd = "INSERT INTO `MolecularTargetBuilder` (molecularTargetId, CNVId) VALUES ('".$class->get_id."', '".$CNV->get_id."');";
	my $sth = $class->{DB}->execute($sql_cmd);
	return 0;
	}	

sub generateCTDescr_r {
	my $class = shift;
	my $NCTid = shift;
	return encode('UTF-8', "В соответствии с молекулярным профилем опухоли, может быть релевантно включение в следующее клиническое исследование");
	}

sub generateTitle_r {
	my $class = shift;
	foreach my $MutationRule ($class->mutationRules) {
		my $symbol = $MutationRule->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol};
		return encode("UTF-8", "Мутация $symbol");
		}
	}

sub generateBiomarkerCode {
	my $class = shift;
	foreach my $MutationRule ($class->mutationRules) {
		my $symbol = $MutationRule->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol};
		return $symbol;
		}
	return undef;
	}

sub variantInterpretations {
	my $class = shift;
	my $sql_cmd = 'SELECT variantInterpretationId from VariantInterpretation where molecularTargetId = '.$class->get_id.';';

	my $sth = $class->{DB}->execute($sql_cmd);
	my @result;
	while (my $row = $sth->fetchrow_arrayref) {
		push @result, Table::VariantInterpretation->fetch($class->{DB}, $$row[0]);
		}
	return @result;
	}

sub gether_phenotype_text {
	my $class = shift;
	my @sentences;
	my %wanted;
	$wanted{pathogenic} = 1;
	$wanted{'likely pathogenic'} = 1;
	$wanted{vus} = 1;
	foreach my $VI ($class->variantInterpretations) {
		next unless defined $VI->info->{interpretationresult};
		next unless defined $wanted{lc($VI->info->{interpretationresult})};
		push @sentences, $VI->format_text;
		}
	return join("\n",@sentences);
	}





















1;
