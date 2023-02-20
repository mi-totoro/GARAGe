package Table::PathoResult;

use strict;
use warnings;
use Dir::Self;
use parent 'Table';
use lib __DIR__;

use Aoddb;
use Atlas;
use File::Basename;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Mojo::Base -base;
use Data::Dumper;

has tablename	=> 'PathoResult';
has id_field	=> 'pathoresultid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;





























1;
