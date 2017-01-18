# Author: Jiwoong Kim (jiwoongbio@gmail.com)
use strict;
use warnings;
use Cwd 'abs_path';
use Getopt::Long;
use List::Util qw(min);

(my $fmapPath = abs_path($0)) =~ s/\/[^\/]*$//;
my $database = loadDefaultDatabase();
my $databasePath = "$fmapPath/FMAP_data/$database";

GetOptions('h' => \(my $help = ''),
	'c' => \(my $cpmInsteadOfRPKM = ''),
	'i=f' => \(my $minimumPercentIdentity = 80),
	'o=s' => \(my $orthologyDefinitionFile = ''),
	'p=s' => \(my $proteinOrthologyFile = ''),
	'd=s' => \$databasePath);
if($help || scalar(@ARGV) == 0) {
	die <<EOF;

Usage:   perl FMAP_quantification.pl [options] blast_hits1.txt [blast_hits2.txt [...]] > abundance.txt

Options: -h       display this help message
         -c       use CPM values instead of RPKM values

EOF
}
$orthologyDefinitionFile = "$fmapPath/FMAP_data/KEGG_orthology.txt" if($databasePath eq "$fmapPath/FMAP_data/$database" && $orthologyDefinitionFile eq '');

my (@inputFileList) = @ARGV;
my %orthologyDefinitionHash = ();
if($orthologyDefinitionFile ne '') {
	open(my $reader, $orthologyDefinitionFile);
	while(my $line = <$reader>) {
		chomp($line);
		my ($orthology, $definition) = split(/\t/, $line);
		$orthologyDefinitionHash{$orthology} = $definition;
	}
	close($reader);
}
my %proteinOrthologyHash = ();
if($proteinOrthologyFile ne '') {
	open(my $reader, $proteinOrthologyFile);
	while(my $line = <$reader>) {
		chomp($line);
		my ($protein, $orthology) = split(/\t/, $line);
		$proteinOrthologyHash{$protein} = $orthology;
	}
	close($reader);
}
my %orthologyHash = ();
my %proteinLengthHash = ();
{
	open(my $reader, "$databasePath.length.txt");
	while(my $line = <$reader>) {
		chomp($line);
		my ($protein, $length) = split(/\t/, $line);
		$orthologyHash{my $orthology = getOrthology($protein)} = 1;
		$proteinLengthHash{$protein} = $length;
	}
	close($reader);
}

my ($readNumber, %orthologyCountHash, %orthologyRpkHash) = (0);
my ($previousReadName, %orthologyProteinLengthHash) = ('');
open(my $reader, "cat @inputFileList | sort --field-separator='\t' -k1,1 |");
while(my $line = <$reader>) {
	chomp($line);
	my ($readName, $protein, $percentIdentity) = split(/\t/, $line);
	next if($percentIdentity < $minimumPercentIdentity);
	if($readName ne $previousReadName) {
		if($previousReadName ne '') {
			if(scalar(my @orthologyList = keys %orthologyProteinLengthHash) == 1) {
				$orthologyCountHash{$_} += 1 foreach(@orthologyList);
				$orthologyRpkHash{$_} += 1 / (min(values %{$orthologyProteinLengthHash{$_}}) * 3 / 1000) foreach(@orthologyList);
			}
			$readNumber += 1;
		}
		($previousReadName, %orthologyProteinLengthHash) = ($readName);
	}
	if(defined($orthologyHash{my $orthology = getOrthology($protein)})) {
		$orthologyProteinLengthHash{$orthology}->{$protein} = $proteinLengthHash{$protein};
	}
}
close($reader);
if($previousReadName ne '') {
	if(scalar(my @orthologyList = keys %orthologyProteinLengthHash) == 1) {
		$orthologyCountHash{$_} += 1 foreach(@orthologyList);
		$orthologyRpkHash{$_} += 1 / (min(values %{$orthologyProteinLengthHash{$_}}) * 3 / 1000) foreach(@orthologyList);
	}
	$readNumber += 1;
}

if($orthologyDefinitionFile ne '') {
	print join("\t", 'orthology', 'definition', 'count', 'rpkm'), "\n";
	foreach my $orthology (sort keys %orthologyHash) {
		my $definition = defined($_ = $orthologyDefinitionHash{$orthology}) ? $_ : '';
		my $count = defined($_ = $orthologyCountHash{$orthology}) ? $_ : 0;
		if($cpmInsteadOfRPKM) {
			my $cpm = $count / ($readNumber / 1000000);
			print join("\t", $orthology, $definition, $count, $cpm), "\n";
		} else {
			my $rpkm = (defined($_ = $orthologyRpkHash{$orthology}) ? $_ : 0) / ($readNumber / 1000000);
			print join("\t", $orthology, $definition, $count, $rpkm), "\n";
		}
	}
} else {
	print join("\t", 'orthology', 'count', 'rpkm'), "\n";
	foreach my $orthology (sort keys %orthologyHash) {
		my $count = defined($_ = $orthologyCountHash{$orthology}) ? $_ : 0;
		if($cpmInsteadOfRPKM) {
			my $cpm = $count / ($readNumber / 1000000);
			print join("\t", $orthology, $count, $cpm), "\n";
		} else {
			my $rpkm = (defined($_ = $orthologyRpkHash{$orthology}) ? $_ : 0) / ($readNumber / 1000000);
			print join("\t", $orthology, $count, $rpkm), "\n";
		}
	}
}

sub loadDefaultDatabase {
	open(my $reader, "$fmapPath/FMAP_data/database");
	chomp(my $line = <$reader>);
	close($reader);
	return $1 if($line =~ /^([A-Za-z0-9_.]+)/);
}

sub getOrthology {
	my ($protein) = @_;
	return $_ if(defined($_ = $proteinOrthologyHash{$protein}));
	return $1 if($protein =~ /^(K[0-9]{5})_/);
	return $protein;
}