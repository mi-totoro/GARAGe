package File::Loci;
#CHR    POS     Count_A Count_C Count_G Count_T Good_depth

use strict;
use warnings;
use Dir::Self;
use parent 'File';
use lib __DIR__;

use Aoddb;
use Atlas;
use File::Basename;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Mojo::Base -base;
use Data::Dumper;

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub position {
	my $class = shift;
	my $chr = shift;
	my $pos = shift;
	if ($chr =~ /(\S+):(\d+)/) {
		$chr = $1;
		$pos = $2;
		}
	open (my $fh , "<", $class->path) or return undef;
	while (<$fh>) {
		my @mas = split/\t/;
		next unless lc($mas[0]) eq lc($chr);
		next unless $mas[1] eq $pos;
		return position->new({'A' => $mas[2],
			'C' => $mas[3],
			'G' => $mas[4],
			'T' => $mas[5],
			'depth' => $mas[6],
			'N' => $mas[6]});
		}
	close $fh;
	return undef;
	}
{
package position;
use Data::Dumper;
use Mojo::Base -base;
has NT   => 'N';
sub new {
	my $class = shift;
	my $data  = shift;
	my $self  = {};
	$self->{info} = $data;
	return (bless $self, $class);
	}
sub sum {
	my $class = shift;
	my $sum = 0;
	map {$sum+=$class->{info}->{$_}} qw(A G C T);
	return $sum;
	}
sub A {
	my $class = shift;
	return position::A->new($class->{info});
	}
sub T {
	my $class = shift;
	return position::T->new($class->{info});
	}
sub G {
	my $class = shift;
	return position::G->new($class->{info});
	}
sub C {
	my $class = shift;
	return position::C->new($class->{info});
	}

sub freq {
	my $class = shift;
	return 0 if $class->sum eq 0;
	return $class->{info}->{$class->NT}/$class->sum;
	}
sub count {
	my $class = shift;
	return $class->{info}->{$class->NT};
	}
}
{
package position::A;
our @ISA = qw(position);
use Mojo::Base -base;
has NT   => 'A';
}
{
package position::T;
our @ISA = qw(position);
use Mojo::Base -base;
has NT   => 'T';
}
{
package position::C;
our @ISA = qw(position);
use Mojo::Base -base;
has NT   => 'C';
}
{
package position::G;
our @ISA = qw(position);
use Mojo::Base -base;
has NT   => 'G';
}















1;
