#!/usr/bin/env perl

use File::Basename;
use Getopt::Long;
use Pod::Usage;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Subfunctions qw(sample_list get_ordered_genotypes get_iupac_code);

if (@ARGV == 0) {
    pod2usage(-verbose => 1);
}

my $runline = "running " . basename($0) . " " . join (" ", @ARGV) . "\n";

my $samplefile = 0;
my $help = 0;
my $cov_thresh = 5;
my $pl_thresh = 0;
my $outfile = "";
my $indels = 0;

GetOptions ('samples|input|vcf=s' => \$samplefile,
            'outputfile=s' => \$outfile,
            'threshold|pl=i' => \$pl_thresh,
            'minimum|coverage|reads=i' => \$cov_thresh,
            'indels' => \$indels,
            'help|?' => \$help) or pod2usage(-msg => "GetOptions failed.", -exitval => 2);

if ($help) {
    pod2usage(-verbose => 1);
}

print $runline;

my $name;
my @samples = ();
my @samplefiles = ();
my %sample_positions = ();

my @AMBIGUOUS_POS = (0,"N",".",0);

if ($samplefile =~ /(.*?)\.vcf$/) {
	@samplefiles = ($1);
} else {
	@samplefiles = @{sample_list ($samplefile)};
}

if ($samplefile =~ /recode\.vcf/) {
	open VCF_FH, "<:crlf", $samplefile or die "couldn't open input file $samplefile.";

	# eat header:
	my $line = readline VCF_FH;
	while ($line =~ m/^#/) {
		$line = readline VCF_FH;
	}

	my $line = readline VCF_FH;
	$line =~ s/#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	//;
	chomp $line;
	@samples = split(/\t/,$line);
	foreach my $sample (@samples) {
		$sample_positions{$sample} = ();
	}
	$line = readline VCF_FH;
	my $i=0;
	while ($line !~ m/^\s*$/) {
		#Chr19	15894518	.	G	A	113.75	.	.	GT:AD:DP:GQ:PL	0/0:20,0:20:60.2:0,60,816	0/0:12,0:12:36.11:0,36,454	0/0:15,0:15:45.09:0,45,555	0/0:10,0:10:30.1:0,30,417	0/0:17,0:17:51.11:0,51,642	0/1:13,3:16:52.21:52,0,434	./.:6,0:6:18.06:0,18,235	0/0:15,0:15:45.14:0,45,578	./.:5,0:5:15.05:0,15,207	0/0:19,0:19:57.03:0,57,634	0/0:10,0:10:30.04:0,30,352	0/0:14,0:15:39.09:0,39,483	0/0:16,0:16:48.15:0,48,621	0/0:14,0:14:42.14:0,42,552	0/0:24,0:24:69.21:0,69,878	0/0:11,0:11:33.11:0,33,437	0/0:14,0:14:42.07:0,42,502	0/0:33,0:33:99:0,99,1054	0/0:23,0:23:69.07:0,69,784	./.:7,0:7:21.07:0,21,285	0/0:21,0:21:63.17:0,63,804	0/0:13,0:13:39.07:0,39,471	0/1:20,4:24:61.58:62,0,652	0/1:18,5:23:74.47:74,0,623	0/0:19,0:19:57.19:0,57,772	0/0:27,0:27:78.1:0,78,904	0/0:22,0:22:66.21:0,66,861	0/0:12,0:12:36.1:0,36,443	0/0:12,0:12:36.05:0,36,415	0/0:11,0:11:30.09:0,30,370	0/0:37,0:37:99:0,111,1304	0/0:17,0:17:51.17:0,51,686	0/0:16,0:16:48.15:0,48,612	0/0:12,0:12:36.08:0,36,433	0/0:14,0:14:36.1:0,36,441	./.:8,0:8:24.08:0,24,328	0/0:19,0:19:57.15:0,57,734	0/0:28,0:28:84.21:0,84,1054	0/0:12,0:12:36.11:0,36,456
		my ($chrom,$pos,undef,$ref,$alt,$qual,$filter,undef,undef,$info) = split (/\t/,$line,10);
		if ($i == 0) {
			$i = $pos;
		}
		while ($i < $pos) {
			for (my $j=0;$j<@samples;$j++) {
				my @this_pos = ();
				push @this_pos, @AMBIGUOUS_POS;
				push @{$sample_positions{$samples[$j]}}, \@this_pos;
			}
			$i++;
		}

		my @pos_info = split (/\t/,$info);
		for (my $j=0;$j<@samples;$j++) {
			my @this_pos = ();
			my @curr_sample_positions = @{$sample_positions{$samples[$j]}};
			$pos_info[$j] =~ /.+?:.+?:(.+?):.+?:(.+)/;
			my $depth = $1;
			my $pl = $2;
			push @this_pos, ($depth,$ref,$alt,$pl);
			push @{$sample_positions{$samples[$j]}}, \@this_pos;
		}
 		$line = readline VCF_FH;
		$i++;
	}
	print "found ".@samples." samples\n";
} else {
	foreach my $sample (@samplefiles) {
		$name = basename($sample);
		my $vcf_file = $sample . ".vcf";
		unless (open (VCF_FH, "<:crlf", $vcf_file)) { next; }

		# eat header:
		my $line = readline VCF_FH;
		while ($line =~ m/^#/) {
			$line = readline VCF_FH;
		}

		my @positions = ();
		my @indels = ();
		#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	GRA10_DNA341.bam
		#chloroplast	1	.	A	.	84	.	DP=18;AF1=7.924e-12;CI95=1.5,0;DP4=18,0,0,0;MQ=59	PL	0
		my $i=1;
		while ($line !~ m/^\s*$/) {
			my @this_pos = ();
			my ($chrom,$pos,undef,$ref,$alt,$qual,$filter,$info,undef,$pl) = split (/\t/,$line);
			while ($i < $pos) {
				push @this_pos, $i, $qual, @AMBIGUOUS_POS;
				push @positions, \@this_pos;
				$i++;
				@this_pos = ();
			}
			if ($line =~ /INDEL/) { # we don't handle indels; drop these lines.
				push @indels, $line;
			} else {
				$info =~ /DP=(.*?);/;
				my $depth = $1;
				chomp $pl;
				$ref =~ s/[Nn]/-/;
				push @this_pos, ($pos,$qual,$depth,$ref,$alt,$pl);
				push @positions, \@this_pos;
				$i++;
			}
			$line = readline VCF_FH;
		}

		close VCF_FH;

		print "processed sample $name with length " . @positions . "\n";
		$sample_positions{$name} = \@positions;
		$sample_positions{$name."_indels"} = \@indels;
		push @samples, $name;
	}
}
my $result_str = "";
foreach my $sample (@samples) {
	my $seq = "";
	my @positions = @{$sample_positions{$sample}};
	my @indels = @{$sample_positions{$name."_indels"}};
	if ($indels == 1) {
		foreach my $line (@indels) {
	# FRE13_HapA.plastome.3.aln.fasta	2	.	TGGG	TGGTTCATGGG	143	.	INDEL;DP=21;VDB=0.0000;AF1=1;AC1=2;DP4=0,0,11,0;MQ=36;FQ=-67.5	PL	184,33,0
			my ($chrom,$pos,undef,$ref,$alt,$qual,$filter,$info,undef,$pl) = split (/\t/,$line);
			chomp $pl;
			my @pls = split(/,/, $pl);
			my @alts = split(/,/, $alt);
			my $alleles = "0";
			for (my $i=1;$i<=@alts;$i++) {
				$alleles = $alleles.$i;
			}
			unshift @alts, $ref;
			my @genotypes = @{get_ordered_genotypes($alleles)};
			my $genotype = "";
			for (my $i=0;$i<@pls;$i++) {
				if ($pls[$i] == 0) {
					$genotype = $genotypes[$i];
					$genotype =~ /(.)(.)/;
					if ($1 != $2) {
						$genotype = "";
					} else {
						$genotype = $alts[$genotype];
					}
				}
			}

			my ($snppos, $snpqual, $depth, $snpref, $snpalt, $snppl) = @{@positions[$pos-1]};
			print "$pos\t$depth\t$qual\t$snpqual\tindels: $genotype\n";
			if ($snppl =~ /0/) {
				$genotype = $snpref;
			} else {
				$genotype = "N";
			}
			my @pls = split(/,/, $snppl);
			my $alleles = "$ref$alt";
			$alleles =~ s/,//g;
			my @genotypes = @{get_ordered_genotypes($alleles)};
			my @newpos = ($pos, $qual, $depth, $genotype, "N", 0);
			@positions[$pos-1] = \@newpos;
		}
	}
	for (my $i=0;$i<@positions; $i++) {
		my ($pos, $qual, $depth, $ref, $alt, $pl) = @{@positions[$i]};
		if ($depth > $cov_thresh) {
			if ($pl =~ /,/) {
				my @pls = split(/,/, $pl);
				my $alleles = "$ref$alt";
				$alleles =~ s/,//g;
				my @alts = ($ref,$alt);
				my @genotypes = @{get_ordered_genotypes($alleles)};
				my $genotype = "";
				for (my $i=0;$i<@pls;$i++) {
					if ($pls[$i] == 0) {
						$genotypes[$i] =~ /(.)(.)/;
						if ($1 eq $2) {
							$genotype = $1;
						} else {
							$genotype = $genotypes[$i];
						}
					}
				}

# 				print "$pos\t$depth\t$qual\t$genotype\n";
				$alt = "N";
				my $genotype = "";
				my @sort_pls = sort @pls;
				my $smallest_pl = shift @sort_pls;
				for (my $g=0;$g<@pls;$g++) {
					if ($pls[$g] == $smallest_pl) {
						$genotype = $genotypes[$g];
						$genotype =~ s/-//g;
						$alt = get_iupac_code($genotype);
					}
				}
				if ($alt !~ /[AGCT]/) {
					print "$pos\t$depth\t$qual\t$genotype = $alt\n";
				}
				$seq .= $alt;
			} elsif ($pl <= $pl_thresh) {
				$seq .= $ref;
			} else {
				$seq .= "N";
			}
		} else {
			print "$pos has depth $depth\n";
			if ($indels != 1) {
				$seq .= "n";
			}
		}
	}

	$result_str .= ">$sample\n$seq\n";

}

if (@samples == 1) {
	unless ($outfile ne "") {
		$outfile = $name;
	}
}

if ($outfile eq "") {
	print "$result_str";
} else {
	open FH, ">", $outfile.".fasta";
	print FH "$result_str";
	close FH;
}



__END__

=head1 NAME

vcf2fasta

=head1 SYNOPSIS

vcf2fasta -samplefile -output [-threshold]

=head1 OPTIONS

  -samples|input|vcf:   name of sample or list of samples to convert
  -outputfile:      optional: prefix of output fasta file
  -threshold|pl:	optional: maximum threshold for Phred-scaled likelihood (lower is best, default is 0)
  -min|coverage:    optional: read depth required to call base (default is 5)

=head1 DESCRIPTION

Converts a VCF file (or files) to a fasta file, using the Phred-scaled likelihood of each genotype call.
=cut

