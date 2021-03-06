#!/usr/bin/perl -w
#-*- perl -*-
#use strict;
use Data::Dumper;

%drugs=();

# load the list of drugs that we are looking for...
sub load_drugs {
    open FILE, "$ARGV[0]" || die "Cant open $ARGV[0] $!";
    while ($line = <FILE>) {
	$line = &remcr($line);
	if (length($line) > 1) {
	    $line =~ tr/[a-z]/[A-Z]/;  # Convert the line to upper case.
            # PPIs:
            if ($line =~ /omeprazole|prilosec|esomeprazole|nexium|pantoprazole|protonix|lansoprazole|prevacid|rabeprazole|aciphex/i ) {
                $drugs{$line} = 0b1000;
                # H2-blockers:
            } elsif ( $line =~ /ranitidine|zantac|famotidine|pepcid|cimetidine|tagamet|axid|nizatidine/i ) {
                $drugs{$line} = 0b0100;
                # Diuretics
            } elsif ( $line =~ /furosemide|lasix|hydrochlorothiazide|hctz|spironolactone|aldactone|torsemide|demadex|acetazolamide|diamox|nizatidine|triamterene|dyrenium|bumetanide|bumex|ethacrynic acid|edecrin|eplerenone|inspra|amiloride|midamor/i ) {
                $drugs{$line} = 0b0010;
            } else {  #should never happen
                print "Danger Will Robinson... '$line' \n";
                die;
            }
        }
    }
    close FILE;
}

&load_drugs();

sub remcr {
    my ($line) = @_;
    while ($line =~ /[\n\r]$/){chop($line);}
    return ($line);
}

sub find_drugs {
    my ($case, $discharge) = @_;
    my $meds = ""; # Contains the section header which indicates that we're still in a medications section
    my $sect = "";
    my $type = "";
    my $ty = 0;
    my $medgroup = 0;
    my $found = 0;
    my $group = 0;
    my $admit = 'unk';
    my $disch = 'unk';
    my $other = 'unk';
    my @words = ();
    my $first = 0, $second = 0, $third = 0, $fourth = 0;

    my @disc = split(/\n/, $discharge);

    $admit = 'unk'; $disch = 'unk'; $other = 'unk'; $ty = 0;
    foreach $line (@disc) {
	$line = &remcr($line);
	$line =~ tr/[a-z]/[A-Z]/;  # Convert the line to upper case.

	## section head in ds
	#if ($line =~ /^((\d|[A-Z])(\.|\)))?\s*([a-zA-Z][a-zA-Z',\.\-\*\d\[\] ]+)(:|;|WERE|IS|INCLUDED|INCLUDING)/)
	if ($line =~ /^((\d|[A-Z])(\.|\)))?\s*([a-zA-Z',\.\-\*\d\[\]\(\) ]+)(:|;|WERE| IS |INCLUDED|INCLUDING)/) {
            print LOGFILE "$case potential section heading:$line\n";
	    $sect = $4;
	    if ($meds) { ## med section ended, now in non-meds section
		#if (!$found){print OFILE "$case|$type|none\n"; }
		$meds = "";
                print LOGFILE "$case meds section ended:$line\n";
	    }
#	    print "---->$3\n";

	    if ($sect =~ /medication|meds/i) { ## new meds section of some type
                print LOGFILE "$case meds section started:$sect\n";
		$meds = $sect;
		$found = 0;
		if ($meds =~ /admission|admitting/i){$type = 'admission'; $ty = 1;}
		elsif ($meds =~ /home|nh|nmeds/i){$type = 'admission'; $ty = 1;}
		elsif ($meds =~ /pre(\-|\s)?(hosp|op)/i){$type = 'admission'; $ty = 1;}
		elsif ($meds =~ /current|previous|outpatient|outpt|outside/i){$type = 'admission'; $ty = 1;}
		elsif ($meds =~ /^[^a-zA-Z]*med(ication)?(s)?/i){$type = 'admission'; $ty = 1;}
		elsif ($meds =~ /transfer|xfer/i){$type = 'transfer'; $ty = 1;}
		elsif ($meds =~ /discharge/i){$type = 'discharge'; $ty = 2;}
		else{$type = $meds; $ty = 3;} ## type other

		if (($ty == 1) && ($admit eq 'unk')){$admit = 'no';} ## unk -> no -> yes
		elsif (($ty == 2) && ($disch eq 'unk')){$disch = 'no';}
		elsif (($ty == 3) && ($other eq 'unk')){$other = 'no';}
	    }

	} elsif ($meds)	{ 	## in meds section, look at line
	    @words = split (/[ ,\.\d\)]+/,$line);
	    foreach $word (@words) {
		$word =~ tr/[a-z]/[A-Z]/;
#                print "$word\n";
		if ($drugs{$word}) {
                    print DRUGFILE "$case|$type|$word\n";
		    #Add to the meds group if you haven't already
		    $medgroup = $medgroup | $drugs{$word};
		    if ($ty == 1){$admit = 'yes';}
		    elsif ($ty == 2){$disch = 'yes';}
		    elsif ($ty == 3){$other = 'yes';}
		    #print OFILE "$case|$type|$line\n";
		    $found = 1;
		}
	    }
	} elsif ($line =~ /medication|meds/i && $line =~ /admission|discharge|transfer/i) {
            print LOGFILE "$case matches medication|meds, but not section heading:$sect\n";
            print "?? $line\n";
        }
    } #END WHILE

    if ($meds && !$found){print OFILE "$case|$type|none\n";} ## also end of med section

    #1) Patient has no medications on admission
    if ($admit =~ /unk/) {
        #    a) Patient has no medications on discharge from the list <--- Loose control (coded as 1)
        if ($disch =~ /no/ || $disch =~ /unk/) {$group = 1;}
        #    b) Patient has medications on discharge from the list     <---- Excluded (coded as 0)
        else {$group = 0;}
    }
    #2) Patient has medications on admission, but none from the list
    elsif ($admit =~ /no/)
    {
        #    a) Patient has no medications on discharge from the list  <--- Tight control (coded as 2)
        if ($disch =~ /no/) {$group = 2;}
        #    b) Patient has no detected discharge medications <--- Loose control (coded as 1)
        elsif ($disch =~ /unk/) {$group = 1;}
        #    c) Patient has medications on discharge from the list      <--- Excluded (coded as 0)
        else {$group = 0;}
    }
    #3) Patient has medications on admission (or "Medications at NH" or "Medications"), and at least one from the list
    else {
        $group = 3;
        #Positive (coded as 3)
    }

    # print "$case,$medgroup\n";
    # printf '<%#b>',  $medgroup;
    # print "\n";

    if (($medgroup & 0b1000) > 0) {$first = 1};
    if (($medgroup & 0b0100) > 0) {$second = 1};
    if (($medgroup & 0b0010) > 0) {$third = 1};

    if ($group == 2 || $group == 3) { print OFILE "$case|||$admit|$disch|$other|$group|$first|$second|$third\n"; }
    #print OFILE "$case|||$admit|$disch|$other|$group|$first|$second|$third|$fourth\n";

} #END SUB

#open output
open (OFILE, ">$ARGV[2]") || die "output $ARGV[2] $!";
print "printing to $ARGV[2]\n";

#open drug file output
open (DRUGFILE, ">drugs.txt") || die "output drugs.txt $!";

#open drug file output
open (LOGFILE, ">nlp.log") || die "output nlp.log $!";

#slurp input
open FILE, "$ARGV[1]" || die "Cant open $ARGV[1] $!";
my $holdTerminator = $/;
undef $/;
$lines = <FILE>;
close FILE;
$/ = $holdTerminator;

#separate output columns
@array = split(/_:-:_/, $lines);
splice(@array, 0, 1);
$size = @array;

for ($i = 0; $i < $size; $i++) {
    if ($i%2 == 0)	{push(@patients, $array[$i]);}
    else {push(@discharges, $array[$i]);}
}

#get the even and odds
@patients = @array[ map 2*$_, 0 .. $#array/2]; # even indices
@discharges = @array[ map 2*$_ + 1, 0 .. $#array/2]; # odd indices

#print join(",", @patients);
#print "\n-----\n";

#MAIN LOOP
print OFILE "SUBJECT_ID|||ADMISSION_MEDS|DISCHARGE_MEDS|OTHER_MEDS|GROUP_ASSIGN|PPI|H2BLOCKERS|DIURETICS\n";
$size = @discharges;
for ($i = 0; $i < $size; $i++) {
#	print "$i... ";
    &find_drugs($patients[$i], $discharges[$i]);
}
close DRUGFILE;
close OFILE;

