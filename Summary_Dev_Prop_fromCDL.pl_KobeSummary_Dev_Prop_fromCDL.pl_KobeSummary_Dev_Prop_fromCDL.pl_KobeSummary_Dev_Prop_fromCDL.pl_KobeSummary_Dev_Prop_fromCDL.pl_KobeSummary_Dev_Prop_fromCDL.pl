#!/usr/bin/perl
#-w
######################################################################################
### Description
###   - summary MOS properties: l/w/nf/fw/usedNumber in hierarchy mode (flatten netlist)
###     from CDL netlist
### Revision History
### v1.0a - 2021/03/08  Leozhao
###   - New created
### v1.1a - 2021/03/12  Leozhao
###   - Add cap info
###   - Add '-hierpath' option to print device hierpath
###
### v1.2a - 2021/05/25  Leozhao
###   - Add prop 'Area', 'STI edge', 'Poly edge' for mos device
###
### v1.3a - 2021/06/17  Leozhao
###   - Add new feature: support to search specified cell, and list hierpath & called number
###
### v1.4a - 2021/10/28  Leozhao
###   - Code enhance, for some gate cell not defined in TECHLIB, but defined in dcpna_analog lib
#######################################################################################

use strict;
use File::Basename;
use Data::Dumper;
use Cwd 'abs_path';
use Getopt::Long;
use CXMT::Common;

my ($cdl,$topcell);
my $searchedcells = "UNDEFINE";
my @searchedcellList;
GetOptions(
    'cdl=s' => \$cdl,
#    'o=s' => \$outputfile,
    'top=s' => \$topcell,
    );

while(my $arg = shift(@ARGV)) {
  if($arg =~ /-cdl$/i) {
    $cdl = shift;
  }elsif($arg =~ /-top$/i) {
    $topcell = shift;
  }elsif($arg =~ /-cell$/i) {
    $searchedcells = shift;
    @searchedcellList = split /\s+/, $searchedcells;
  }
}


if(!$cdl || !$topcell) {
  help();
  exit 1;
}

my $repdir = ".devSizeInfo";
if(not -d $repdir) {
  system("mkdir $repdir");
}
my $mosrep = "$repdir/$topcell.mos.csv";
#my $resrep = "$repdir/$topcell.res.csv";
#my $diorep = "$repdir/$topcell.dio.csv";
#my $bjtrep = "$repdir/$topcell.bjt.csv";
#my $caprep = "$repdir/$topcell.cap.csv";
my $mosgeb = "$repdir/$topcell.mos.geb";
#my $resgeb = "$repdir/$topcell.res.geb";
#my $diogeb = "$repdir/$topcell.dio.geb";
#my $bjtgeb = "$repdir/$topcell.bjt.geb";
#my $capgeb = "$repdir/$topcell.cap.geb";
#my $searchrep = "$repdir/$topcell.${searchedcell}.geb";

sub help {
  print <<EOF;
****************************************************************
=> Usage:
    % script -> $0

    % Summary_Dev_Prop_fromCDL.pl -cdl <cdl netlist> 
                                  -top <top_cell>
                                  [-cell <searched_cells_list>]
    eg: Summary_Dev_Prop_fromCDL.pl -cdl LP4TOP.cdl -top LP4TOP -cell "aa bb cc"

****************************************************************
EOF
}

my $bgn=`date +%s`; chomp($bgn);

open(IN, "<$cdl") or die "Cannot open netlist file: $cdl for read";
my @contents=<IN>;
close IN;

my $devSum = {};
my $sktCalled = {}; ## hash to store subckt called time in topcell
## remove '+' symbol
my @upContents=removePlusSymbol();
print @upContents;
## get all mos hierarchy
my $topLevel={};
my $capskt = {};
my $sktInfo = getDevHier_1st();
my $bgate = {};
my $resskt = {};
my $devHier = getDevHier_2nd();
#print "sktInfo: \n";
#print Dumper(\%$sktInfo);
#print "[INFO] top cell : $topcell\n";
#print "devHier:\n";
#print Dumper(\%$devHier);
#print "topLevel: \n";
#print Dumper(\%$topLevel);
#print "bgate: \n";
#print Dumper(\%$bgate);## bgate -- WP/WN

traceDevHier();
#print Dumper(\%$devHier);
#print Dumper(\%$devSum);
#print Dumper(\%$resskt);
#print Dumper(\%$sktCalled);
devHieroutput();

my $end=`date +%s`; chomp($end);
my $runtime=$end-$bgn;
printf("Total Run Time:  %.1fm\n", eval($runtime/60));


sub devHieroutput {
  ## mos output
  if(defined $devSum->{mos}) {
    open(MOSOUT, ">$mosrep") or die $!;
    open(MOSGEB, ">$mosgeb") or die $!;
    printf(MOSOUT "Device,TotalWidth(um),FingerWidth(um),nf,Length(um),UsedNumber,Area(um^2),STI_edge(um),Poly_edge(um)\n");
    printf(MOSGEB "num,hierpath,inst,instName,device,totalWidth(um),fingerWidth(um),nf,length(um),lib,cell,deviceUsedNumberInCell,deviceUsedNumberInTop\n");
    my $num = 1;
    foreach my $m (sort keys %{$devSum->{mos}}) {
      foreach my $prop (sort keys %{$devSum->{mos}->{$m}}) {
        my ($l, $w, $nf) = split /:/, $prop;
        my $count = $devSum->{mos}->{$m}->{$prop}->{count};
        my $fw = $w/$nf;
        my $area = $w*$l*$count;
        my $sti_edge = $l*$count*$nf*2;
        my $poly_edge = $fw*$count*$nf*2;
        printf(MOSOUT "$m,$w,$fw,$nf,$l,$count,$area,$sti_edge,$poly_edge\n");
        foreach my $skt (sort keys %{$devSum->{mos}->{$m}->{$prop}->{hierpath}}) {
          my $lib = $sktInfo->{$skt}->{lib};
          my $cell = $sktInfo->{$skt}->{cell};
          my $path = $devSum->{mos}->{$m}->{$prop}->{hierpath}->{$skt}->{path};
          my $cellCount = $devSum->{mos}->{$m}->{$prop}->{hierpath}->{$skt}->{count};
          my ($hp, $inst) = Get_hierpath_and_inst($path);
          printf(MOSGEB "$num,$hp,inst,$inst,$m,$w,$fw,$nf,$l,$lib,$cell,$cellCount,$count\n");
          $num++;
        }
      }
    }
    close MOSOUT;
    close MOSGEB;
    print "  MOS size info : $mosrep    (report for device review)\n";
    print "                  $mosgeb    (report for design review)\n";
  }else{
    print "[WARNING] NOT found MOS in $topcell\n";
  }
  ## res output
#  if(defined $devSum->{res}) {
#    open(RESOUT, ">$resrep") or die $!;
#    open(RESGEB, ">$resgeb") or die $!;
#    printf(RESOUT "Device,Width(um),Length(um),ContNumber,UsedNumber\n");
#    printf(RESGEB "num,hierpath,inst,instName,device,width(um),length(um),contNumber,lib,cell,deviceUsedNumberInCell,deviceUsedNumberInTop\n");
#    my $num = 1;
#    foreach my $r (sort keys %{$devSum->{res}}) {
#      foreach my $prop (sort keys %{$devSum->{res}->{$r}}) {
#        my ($l, $w, $nm, $n) = split /:/, $prop;
#        my $contNum = $nm;
#        if($contNum == 0) { $contNum = $n; };
#        my $count = $devSum->{res}->{$r}->{$prop}->{count};
#        my $out = "$r,$w,$l,$contNum,$count";
#        while($out =~ /,0,/) {
#          $out =~ s/,0,/,,/;
#        }
#        printf(RESOUT "$out\n");
#        foreach my $skt (sort keys %{$devSum->{res}->{$r}->{$prop}->{hierpath}}) {
#          my $lib = $sktInfo->{$skt}->{lib};
#          my $cell = $sktInfo->{$skt}->{cell};
#          my $path = $devSum->{res}->{$r}->{$prop}->{hierpath}->{$skt}->{path};
#          my $cellCount = $devSum->{res}->{$r}->{$prop}->{hierpath}->{$skt}->{count};
#          my ($hp, $inst) = Get_hierpath_and_inst($path);
#          my $tmpout = $out;
#          $tmpout =~ s/,[^,]+$//;  ## remove $count
#          printf(RESGEB "$num,$hp,inst,$inst,$tmpout,$lib,$cell,$cellCount,$count\n");
#          $num++;
#        }
#      }
#    }
#    close RESOUT;
#    close RESGEB;
#    print "  RES size info : $resrep    (report for device review)\n";
#    print "                  $resgeb    (report for design review)\n";
#  }else{
#    print "[WARNING] NOT found RES in $topcell\n";
#  }
#  ## dio output
#  if(defined $devSum->{dio}) {
#    open(DIOOUT, ">$diorep") or die $!;
#    open(DIOGEB, ">$diogeb") or die $!;
#    printf(DIOOUT "Device,Area(u^2),PJ(um),UsedNumber\n");
#    printf(DIOGEB "num,hierpath,inst,instName,device,area(um^2),pj(um),lib,cell,deviceUsedNumberInCell,deviceUsedNumberInTop\n");
#    my $num = 1;
#    foreach my $d (sort keys %{$devSum->{dio}}) {
#      foreach my $prop (sort keys %{$devSum->{dio}->{$d}}) {
#        my ($area, $pj) = split /:/, $prop;
#        my $count = $devSum->{dio}->{$d}->{$prop}->{count};
#        my $out = "$d,$area,$pj,$count";
#        while($out =~ /,0,/) {
#          $out =~ s/,0,/,,/;
#        }
#        printf(DIOOUT "$out\n");
#        foreach my $skt (sort keys %{$devSum->{dio}->{$d}->{$prop}->{hierpath}}) {
#          my $lib = $sktInfo->{$skt}->{lib};
#          my $cell = $sktInfo->{$skt}->{cell};
#          my $path = $devSum->{dio}->{$d}->{$prop}->{hierpath}->{$skt}->{path};
#          my $cellCount = $devSum->{dio}->{$d}->{$prop}->{hierpath}->{$skt}->{count};
#          my ($hp, $inst) = Get_hierpath_and_inst($path);
#          my $tmpout = $out;
#          $tmpout =~ s/,[^,]+$//;
#          printf(DIOGEB "$num,$hp,inst,$inst,$tmpout,$lib,$cell,$cellCount,$count\n");
#          $num++;
#        }
#      }
#    }
#    close DIOOUT;
#    close DIOGEB;
#    print "  DIO size info : $diorep    (report for device review)\n";
#    print "                  $diogeb    (report for design review)\n";
#  }else{
#    print "[WARNING] NOT found DIODE in $topcell\n";
#  }
#  ## bjt output
#  if(defined $devSum->{bjt}) {
#    open(BJTOUT, ">$bjtrep") or die $!;
#    open(BJTGEB, ">$bjtgeb") or die $!;
#    printf(BJTOUT "Device,Area(u^2),UsedNumber\n");
#    printf(BJTGEB "num,hierpath,inst,instName,device,area(um^2),lib,cell,deviceUsedNumberInCell,deviceUsedNumberInTop\n");
#    my $num = 1;
#    foreach my $b (sort keys %{$devSum->{bjt}}) {
#      foreach my $prop (sort keys %{$devSum->{bjt}->{$b}}) {
#        my $area = $prop;
#        my $count = $devSum->{bjt}->{$b}->{$prop}->{count};
#        printf(BJTOUT "$b,$area,$count\n");
#        foreach my $skt (sort keys %{$devSum->{bjt}->{$b}->{$prop}->{hierpath}}) {
#          my $lib = $sktInfo->{$skt}->{lib};
#          my $cell = $sktInfo->{$skt}->{cell};
#          my $path = $devSum->{bjt}->{$b}->{$prop}->{hierpath}->{$skt}->{path};
#          my $cellCount = $devSum->{bjt}->{$b}->{$prop}->{hierpath}->{$skt}->{count};
#          my ($hp, $inst) = Get_hierpath_and_inst($path);
#          printf(BJTGEB "$num,$hp,inst,$inst,$b,$area,$lib,$cell,$cellCount,$count\n");
#          $num++;
#        }
#      }
#    }
#    close BJTOUT;
#    close BJTGEB;
#    print "  BJT size info : $bjtrep    (report for device review)\n";
#    print "                  $bjtgeb    (report for design review)\n";
#  }else{
#    print "[WARNING] NOT found BJT in $topcell\n";
#  }
#  ## cap output
#  if(defined $devSum->{cap}) {
#    open(CAPOUT, ">$caprep") or die $!;
#    open(CAPGEB, ">$capgeb") or die $!;
#    printf(CAPOUT "Device,nc,nr,UsedNumber\n");
#    printf(CAPGEB "num,hierpath,inst,instName,device,nc,nr,lib,cell,deviceUsedNumberInCell,cellUsedNumberInTop,deviceUsedNumberInTop\n");
#    #printf(CAPGEB "num,hierpath,inst,instName,device,nc,nr,lib,cell,deviceUsedNumberInCell,deviceUsedNumberInTop\n");
#    my $num = 1;
#    foreach my $c (sort keys %{$devSum->{cap}}) {
#      foreach my $prop (sort keys %{$devSum->{cap}->{$c}}) {
#        my ($nc, $nr) = split /:/, $prop;
#        my $count = $devSum->{cap}->{$c}->{$prop}->{count};
#        printf(CAPOUT "$c,$nc,$nr,$count\n");
#        foreach my $skt (sort keys %{$devSum->{cap}->{$c}->{$prop}->{hierpath}}) {
#          my $lib = $sktInfo->{$skt}->{lib};
#          my $cell = $sktInfo->{$skt}->{cell};
#          my $path = $devSum->{cap}->{$c}->{$prop}->{hierpath}->{$skt}->{path};
#          my $cellCount = $devSum->{cap}->{$c}->{$prop}->{hierpath}->{$skt}->{count};
#          my ($hp, $inst) = Get_hierpath_and_inst($path);
#          printf(CAPGEB "$num,$hp,inst,$inst,$c,$nc,$nr,$lib,$cell,$cellCount,$sktCalled->{$cell}->{calledNumber},$count\n");
#          #printf(CAPGEB "$num,$hp,inst,$inst,$c,$nc,$nr,$lib,$cell,$cellCount,$count\n");
#          $num++;
#        }
#      }
#    }
#    close CAPOUT;
#    close CAPGEB;
#    print "  CAP size info : $caprep    (report for device review)\n";
#    print "                  $capgeb    (report for design review)\n";
#  }
#  ## search cell
#  if(defined $devSum->{searchedcell}) {
#    foreach my $searchedcell (keys %{$devSum->{searchedcell}}) {
#      my $searchrep = "$repdir/$topcell.${searchedcell}.geb";
#      open(SEARCH, ">$searchrep") or die $!;
#      printf(SEARCH "num,hierpath,inst,instName,searchedCell,lib,cell,usedNumInCell,upperCellUsedNumberInTop,usedNumInTop\n");
#      my $num = 1;
#      foreach my $skt (sort keys %{$devSum->{searchedcell}->{$searchedcell}->{justkeyword}->{hierpath}}) {
#        my $lib = $sktInfo->{$skt}->{lib};
#        my $cell = $sktInfo->{$skt}->{cell};
#        my $path = $devSum->{searchedcell}->{$searchedcell}->{justkeyword}->{hierpath}->{$skt}->{path};
#        my $cellCount = $devSum->{searchedcell}->{$searchedcell}->{justkeyword}->{hierpath}->{$skt}->{count};
#        my ($hp, $inst) = Get_hierpath_and_inst($path);
#        printf(SEARCH "$num,$hp,inst,$inst,$searchedcell,$lib,$cell,$cellCount,$sktCalled->{$cell}->{calledNumber},$devSum->{searchedcell}->{$searchedcell}->{justkeyword}->{count}\n");
#        $num++;
#      }
#      close SEARCH;
#      print "  SEARCH Cell info : $searchrep\n";
#    }
#  }else{
#    print "[WARNING] NOT found CAP in $topcell\n";
#  }
}

sub grepMosParamValueInGateCell {
  my ($inst, $mosInfo, $param) = @_;
  my ($mosInst, $mosType, $mosParam) = split /:/, $mosInfo;
  my ($w,$l,$nf);
  if($mosParam =~ /w\s*=\s*(\S+)/i) { $w = $1; }
  if($mosParam =~ /l\s*=\s*(\S+)/i) { $l = $1; }
  if($mosParam =~ /nf\s*=\s*(\S+)/i) { $nf = $1; }
  my $paramHash = {};
  $param =~ s/\s*=\s*/=/g;
  $param =~ s/^\s*//;
  $param =~ s/\s*$//;
  my @plist = split /\s+/, $param;
  foreach (@plist) {
    my ($tmpA, $tmpV) = split /=/;
    $paramHash->{$tmpA} = $tmpV;
  }
  #print Dumper(\%$paramHash);
  #print "w: $w  -- l: $l  --  nf: $nf\n";
  $w = $paramHash->{$w};
  $w = unitalign($w);
  $l = $paramHash->{$l};
  $l = unitalign($l);
  $nf = $paramHash->{$nf};
  $nf = unitalign($nf);
  my @retval = ("$inst.$mosInst", $mosType, "$l:$w:$nf");
  return(@retval);
}

sub grepResParamValueInResSkt {
  my ($inst, $resInfo, $param) = @_;
  my ($resInst, $resType, $resParam) = split /:/, $resInfo;
  my ($w,$l,$nm,$n) = (0,0,0,0);
  if($resParam =~ /w\s*=\s*(\S+)/i) { $w = $1; }
  if($resParam =~ /l\s*=\s*(\S+)/i) { $l = $1; }
  if($resParam =~ /nm\s*=\s*(\S+)/i) { $nm = $1; }
  if($resParam =~ /n\s*=\s*(\S+)/i) { $n = $1; }
  my $paramHash = {};
  $param =~ s/\s*=\s*/=/g;
  $param =~ s/^\s*//; $param =~ s/\s*$//;
  my @plist = split /\s+/, $param;
  foreach (@plist) {
    my ($tmpA, $tmpV) = split /=/;
    $paramHash->{$tmpA} = $tmpV;
  }
  $w = $paramHash->{$w} if defined $paramHash->{$w};
  $w = unitalign($w);
  $l = $paramHash->{$l} if defined $paramHash->{$l};
  $l = unitalign($l);
  $nm = $paramHash->{$nm} if defined $paramHash->{$nm};
  $nm = unitalign($nm);
  $n = $paramHash->{$n} if defined $paramHash->{$n};
  $n = unitalign($n);
  my @retval = ("$inst.$resInst", $resType, "$l:$w:$nm:$n");
  return(@retval);
}

sub devCountSummary {
  my ($hierpath, $type, $dev, $psum, $skt, $upperLevel) = @_;  ## $skt - device in which subckt
  my $tmphp = "TOP.$hierpath";  ## why add prefix 'TOP.', maybe device or gate cell in top cell
  if($upperLevel == 1) { ## upperLevel would be 1 or 2, 1 means device, only need to chop last device name. eg: xxx.MN0 -> xxx
    $tmphp =~ s/\.[^\.]+$//;
  }elsif($upperLevel == 2) {  ## 2 means gate cell, or CXcap2S60x97 such cells, need to chop last two inst.device name, eg: xxx.XI_invLx1.MN0 -> xxx
    $tmphp =~ s/\.[^\.]+\.[^\.]+$//;
  }
  #print "$tmphp\n";
  if(defined $sktCalled->{$skt}) {
    if(not defined $sktCalled->{$skt}->{allHierPath}->{$tmphp}) {
      $sktCalled->{$skt}->{calledNumber} = $sktCalled->{$skt}->{calledNumber} + 1;
      $sktCalled->{$skt}->{allHierPath}->{$tmphp} = 1;
    }
  }else{
    $sktCalled->{$skt}->{calledNumber} = 1;
    #push @{$sktCalled->{$skt}->{allHierPath}}, $tmphp;
    $sktCalled->{$skt}->{allHierPath}->{$tmphp} = 1;
  }
  if(defined $devSum->{$type} && defined $devSum->{$type}->{$dev} && defined $devSum->{$type}->{$dev}->{$psum}) {
    $devSum->{$type}->{$dev}->{$psum}->{count} = $devSum->{$type}->{$dev}->{$psum}->{count} + 1;
    #push @{$devSum->{$type}->{$dev}->{$psum}->{hierpath}}, $hierpath;   ##  TODO comment to reduce hash size, can open it when needed
    if(defined $devSum->{$type}->{$dev}->{$psum}->{hierpath}->{$skt}) {
      $devSum->{$type}->{$dev}->{$psum}->{hierpath}->{$skt}->{count} = $devSum->{$type}->{$dev}->{$psum}->{hierpath}->{$skt}->{count} + 1;
    }else{
      $hierpath =~ s/\.M+/\.M/i; $hierpath =~ s/^M+/M/i;
      $hierpath =~ s/\.R+/\.R/i; $hierpath =~ s/^R+/R/i;
      $hierpath =~ s/\.D+/\.D/i; $hierpath =~ s/^D+/D/i;
      $hierpath =~ s/\.Q+/\.Q/i; $hierpath =~ s/^Q+/Q/i;
      $hierpath =~ s/\.C+/\.C/i; $hierpath =~ s/^C+/C/i;
      $devSum->{$type}->{$dev}->{$psum}->{hierpath}->{$skt}->{path} = $hierpath;
      $devSum->{$type}->{$dev}->{$psum}->{hierpath}->{$skt}->{count} = 1;
    }
  }else{
    $devSum->{$type}->{$dev}->{$psum}->{count} = 1;
    #push @{$devSum->{$type}->{$dev}->{$psum}->{hierpath}}, $hierpath;
    $hierpath =~ s/\.M+/\.M/i; $hierpath =~ s/^M+/M/i;
    $hierpath =~ s/\.R+/\.R/i; $hierpath =~ s/^R+/R/i;
    $hierpath =~ s/\.D+/\.D/i; $hierpath =~ s/^D+/D/i;
    $hierpath =~ s/\.Q+/\.Q/i; $hierpath =~ s/^Q+/Q/i;
    $hierpath =~ s/\.C+/\.C/i; $hierpath =~ s/^C+/C/i;
    $devSum->{$type}->{$dev}->{$psum}->{hierpath}->{$skt}->{path} = $hierpath;
    $devSum->{$type}->{$dev}->{$psum}->{hierpath}->{$skt}->{count} = 1;
  }
}

sub handleMosList {
  my ($hierpath, $upperCell, $cell, $mos) = @_;
  if($mos =~ /=\s*W[NP]/i) {  # MMN2:ntn:W=WN2 L=LN2 nf=nfN2
    my $lastInst=$hierpath;
    if($hierpath =~ /\S*\.(\S+)\s*$/) { $lastInst = $1; }
    if(not defined $bgate->{$upperCell}->{$lastInst}) {
      print "[ERROR]: cannot find basic gate - $lastInst in subckt - $upperCell\n";
      exit 1;
    }else{
      my $param = $bgate->{$upperCell}->{$lastInst};
      #print "hierpath: $hierpath -- mos: $mos -- param: $param\n";
      my ($mosHierpath, $mosType, $psum) = grepMosParamValueInGateCell($hierpath, $mos, $param);
      devCountSummary($mosHierpath,"mos",$mosType,$psum,$upperCell,2);  ## Use 'upperCell' here, find gate cell used in which cell
    }
  }else{  ## MMP4:ptn:W=0.75u L=0.2u nf=1
    my ($mosInst, $mosType, $mosParam) = split /:/, $mos;
    #print "mosInst: $mosInst --  mosType: $mosType  --  mosParam: $mosParam\n";
    my ($w,$l,$nf);
    if($mosParam =~ /w\s*=\s*(\S+)/i) { $w = unitalign($1); }
    if($mosParam =~ /l\s*=\s*(\S+)/i) { $l = unitalign($1); }
    if($mosParam =~ /nf\s*=\s*(\S+)/i) { $nf = unitalign($1) ; }
    my $psum = "${l}:${w}:$nf";
    #print "$hierpath.$mosInst - $mosParam\n";
    devCountSummary("$hierpath.$mosInst", "mos", $mosType, $psum, $cell, 1);
  }
}

sub handleResList {
  my ($hierpath, $upperCell, $cell, $res) = @_;
  if($res =~ /=\s*[a-zA-Z]/) { ## 'RR7:rndiff_3t:w=w l=l flag_res=0 nm=4 '
    my $lastInst = $hierpath;
    if($hierpath =~ /\S*\.(\S+)\s*$/) { $lastInst = $1; }
    if(not defined $resskt->{$upperCell}->{$lastInst}) {
      print "[ERROR]: cannot find resistaor subckt - $lastInst in subckt - $upperCell\n";
      exit 1;
    }else{
      my $param = $resskt->{$upperCell}->{$lastInst};
      my ($resHierpath, $resType, $psum) = grepResParamValueInResSkt($hierpath, $res, $param);
      devCountSummary($resHierpath, "res", $resType, $psum, $upperCell, 2);  ## Use 'upperCell' here, find 4t/5t res used in which cell
    }
  }else{  ## $res - 'RR0:rndiff_3t:w=0.16u l=18.7u flag_res=1 nm=4 '
    my ($resInst, $resType, $resParam) = split /:/, $res;
    my ($w,$l,$nm,$n) = (0,0,0,0);
    if($resParam =~ /w\s*=\s*(\S+)/i) { $w = unitalign($1); }
    if($resParam =~ /l\s*=\s*(\S+)/i) { $l = unitalign($1); }
    if($resParam =~ /nm\s*=\s*(\S+)/i) { $nm = unitalign($1); }
    if($resParam =~ /n\s*=\s*(\S+)/i) { $n = unitalign($1); }
    my $psum = "${l}:${w}:${nm}:$n";
    devCountSummary("$hierpath.$resInst", "res", $resType, $psum, $cell, 1);
  }
}

sub handleDioList {
  my ($hierpath, $upperCell, $cell, $dio) = @_;
  my ($dioInst, $dioType, $dioParam) = split /:/, $dio;  ##  'DDD0:d_pwdnw_ckt:0:0'
  my ($area, $pj) = (0,0);
  if($dioParam =~ /area\s*=\s*(\S+)/i) { $area = unitalign($1)*1E6; }
  if($dioParam =~ /pj\s*=\s*(\S+)/i) { $pj = unitalign($1); }
  my $psum = "${area}:$pj";
  #print "$hierpath.$dioInst    --  $cell\n";
  devCountSummary("$hierpath.$dioInst", "dio", $dioType, $psum, $cell, 1);
}

sub handleBjtList {
  my ($hierpath, $upperCell, $cell, $bjt) = @_;
  my ($bjtInst, $bjtType, $bjtParam) = split /:/, $bjt;  ##  'QQ1<7>:pnp10a36_ckt:area=31.5e-12 '
  my ($area) = (0);
  if($bjtParam =~ /area\s*=\s*(\S+)/i) { $area = unitalign($1)*1E6; }
  my $psum = "$area";
  devCountSummary("$hierpath.$bjtInst", "bjt", $bjtType, $psum, $cell, 1);
}

sub handleCapList {
  my ($hierpath, $upperCell, $cell, $cap) = @_;
  my ($capInst, $capType, $capParam) = split /:/, $cap; ## 'CC1 net3 IOb nicap_2t nc=60 nr=49'
  my ($nc, $nr) = (0, 0);
  if($capParam =~ /nc\s*=\s*(\S+)/i) { $nc = $1; }
  if($capParam =~ /nr\s*=\s*(\S+)/i) { $nr = $1; }
  my $psum = "${nc}:$nr";
  devCountSummary("$hierpath.$capInst", "cap", $capType, $psum, $cell, 1);
}

sub handleSearchedcellList {
  my ($hierpath, $upperCell, $cell, $scInfo) = @_;
  my ($scInst, $scell) = split /::/, $scInfo;
  my $psum = "justkeyword";
  devCountSummary("$hierpath.$scInst", "searchedcell", $scell, $psum, $cell, 1);
}

sub traceDevHier {
  foreach my $topInst (keys %$topLevel) {
    my $instancedCell=$topLevel->{$topInst}->{cell};
    ## mos inside $instancedCell
    if(defined $devHier->{$instancedCell}->{mos}) {
      foreach my $mos (@{$devHier->{$instancedCell}->{mos}}) {
        handleMosList($topInst, $topcell, $instancedCell, $mos);
      }
    }
    ## res inside $instancedCell
#    if(defined $devHier->{$instancedCell}->{res}) {
#      foreach my $res (@{$devHier->{$instancedCell}->{res}}) {
#        handleResList($topInst, $topcell, $instancedCell, $res);
#      }
#    }
#    ## dio inside $instancedCell
#    if(defined $devHier->{$instancedCell}->{dio}) {
#      foreach my $dio (@{$devHier->{$instancedCell}->{dio}}) {
#        handleDioList($topInst, $topcell, $instancedCell, $dio);
#      }
#    }
#    ## bjt inside $instancedCell
#    if(defined $devHier->{$instancedCell}->{bjt}) {
#      foreach my $bjt (@{$devHier->{$instancedCell}->{bjt}}) {
#        handleBjtList($topInst, $topcell, $instancedCell, $bjt);
#      }
#    }
#    ## cap inside $instancedCell
#    if(defined $devHier->{$instancedCell}->{cap}) {
#      foreach my $cap (@{$devHier->{$instancedCell}->{cap}}) {
#        handleCapList($topInst, $topcell, $instancedCell, $cap);
#      }
#    }
    ## searched cell inside $instancedCell
    if(defined $devHier->{$instancedCell}->{searchedcell}) {
      foreach my $sc (@{$devHier->{$instancedCell}->{searchedcell}}) {
        handleSearchedcellList($topInst, $topcell, $instancedCell, $sc);
      }
    }
    ## X inst inside $instancedCell
    if(defined $devHier->{$instancedCell}->{inst}) {
      foreach my $inst (keys %{$devHier->{$instancedCell}->{inst}}) {
        traceDevHierLoop("$topInst.$inst", $instancedCell, $devHier->{$instancedCell}->{inst}->{$inst});
      }
    }
  }
}

sub traceDevHierLoop {
  my ($hierpath, $upperCell, $cell) = @_;
  if(defined $devHier->{$cell}->{mos}) {
    foreach my $mos (@{$devHier->{$cell}->{mos}}) {
      handleMosList($hierpath,$upperCell,$cell,$mos);
    }
  }
#  if(defined $devHier->{$cell}->{res}) {
#    foreach my $res (@{$devHier->{$cell}->{res}}) {
#      handleResList($hierpath,$upperCell,$cell,$res);
#    }
#  }
#  if(defined $devHier->{$cell}->{dio}) {
#    foreach my $dio (@{$devHier->{$cell}->{dio}}) {
#      handleDioList($hierpath,$upperCell,$cell,$dio);
#    }
#  }
#  if(defined $devHier->{$cell}->{bjt}) {
#    foreach my $bjt (@{$devHier->{$cell}->{bjt}}) {
#      handleBjtList($hierpath,$upperCell,$cell,$bjt);
#    }
#  }
#  if(defined $devHier->{$cell}->{cap}) {
#    foreach my $cap (@{$devHier->{$cell}->{cap}}) {
#      handleCapList($hierpath,$upperCell,$cell,$cap);
#    }
#  }
  if(defined $devHier->{$cell}->{searchedcell}) {
    foreach my $sc (@{$devHier->{$cell}->{searchedcell}}) {
      handleSearchedcellList($hierpath, $upperCell, $cell, $sc);
    }
  }
  if(defined $devHier->{$cell}->{inst}) {
    foreach my $inst (keys %{$devHier->{$cell}->{inst}}) {
      traceDevHierLoop("$hierpath.$inst",$cell, $devHier->{$cell}->{inst}->{$inst});
    }
  }
}

sub getDevHier_1st {
  my $hier={};
  my $lib;
  my $cell;
  my $sktName;
  my $sktFlag = 0;
  foreach (@upContents) {
    chomp;
    if(/^\s*\*\s+Library\s+Name$hier->{$sktName}->{instORdevFlag}\s*:\s*(\S+)/i) {
      $lib=$1;
    }elsif(/^\s*\.subckt\s+(\S+)/i) {
      $sktName=$1;
      $sktFlag=1;
      $hier->{$sktName}->{lib}=$lib;
      $hier->{$sktName}->{cell}=$sktName;
    }elsif($sktFlag == 1 && /^\s*([XMRDQC]\S+)\s+/i) {  ## instance or device: mos/res/diode/bjt/cap
      $hier->{$sktName}->{instORdevFlag}=1;
      if(/^\s*C/i && not defined $capskt->{$sktName}) {  ## define nicap subckt cell group, like 'CXcap2S60x49 ...', designer want to konw such cell called situation in fullchip
        $capskt->{$sktName} = 1;
      }
    }elsif($sktFlag == 1 && /^\s*\.ends/) {
      $sktFlag=0;
    }
  }
  return($hier);
}


sub getDevHier_2nd {
  my $hier={};
  my ($libName,$cellName,$viewName,$sktName);
  my ($sktFlag) = (0);
  foreach (@upContents) {
    chomp;
    next if /^\s*X.*\s+brknet(\S*)\s*$/i;  ## skip brknet instances
    if(/^\s*\*\s+Library\s+Name\s*:\s*(\S+)\s*/i) {
      $libName=$1;
    }elsif(/^\s*\*\s+View\s+Name\s*:\s*(\S+)\s*/i) {
      $viewName=$1;
    }elsif(/^\s*\.subckt\s+(\S+)/i) {
      $sktName=$1;
      $sktFlag=1;
      $hier->{$sktName}->{lib}=$libName;
      $hier->{$sktName}->{cell}=$sktName;
      $hier->{$sktName}->{view}=$viewName;
    }elsif($sktFlag == 1 && /^\s*[XMRDQC]\S+\s+/i && $sktName ne $topcell) {  ## NOT inside top cell
      if(/^\s*(X\S+)\s+[^=]*?\s+([^ =]+)\s*(\S+\s*=.*)?\s*$/i) {
        my ($instName, $instancedCell, $param) = ($1,$2,$3);
        #print "$instName -- $instancedCell -- $param\n";
        #print "$instancedCell  -- $sktInfo->{$instancedCell}->{lib}  --  $sktInfo->{$instancedCell}->{instORdevFlag}\n";
        #if($sktInfo->{$instancedCell}->{lib} eq "TECHLIB" && $param && $param =~ /W[PN]/i) {  ## like inv in stdcells_am/invLx1
        if($param && $param =~ /W[PN]\d*\s*=/i) {  ## like inv in stdcells_am/invLx1
          ## in dcpna, some gate cell not only defined in TECHLIB, but also dcpna_analog lib
          ## dcpna_analog/passgt_ntn
          $bgate->{$sktName}->{$instName} = $param;
        }elsif($sktInfo->{$instancedCell}->{lib} eq "TECHLIB" && $param && $param =~ /l\s*=/i) {   ## 5T res: XI_RNPDIFF5t_3 net5 net4 A B vss! / RNPDIFF5t n1=4 n2=4 l=4.7u w=0.16u
          $resskt->{$sktName}->{$instName} = $param;
        }
        if(defined $sktInfo->{$instancedCell}->{instORdevFlag} && $sktInfo->{$instancedCell}->{instORdevFlag} == 1) {
          $hier->{$sktName}->{inst}->{$instName}=$instancedCell;
        }
        foreach my $searchedcell (@searchedcellList) {
          if(lc($instancedCell) eq lc($searchedcell)) {
            push @{$hier->{$sktName}->{searchedcell}}, "${instName}::$searchedcell";
          }
        }
      }elsif(/^\s*(M\S+)\s+.*\s+([^ =]+)\s+(\S+\s*=.*)\s*$/i) {  ## mos
        my ($mosInstname, $mosType, $param) = ($1, $2, $3);
        #print "$mosInstname -- $mosType -- $param\n";
        push @{$hier->{$sktName}->{mos}}, "$mosInstname:$mosType:$param";
      }elsif(/^\s*(R\S+)\s+.*\s+([^ =]+)\s+(\S+\s*=.*)\s*$/i) {  ## res
        my ($resInstname, $resType, $param) = ($1, $2, $3);
        next if $resType =~ /^brknet$/i;   ## skip brknet, in DBRMA, XDecG1_8G use brknet directly
        push @{$hier->{$sktName}->{res}}, "$resInstname:$resType:$param";
      }elsif(/^\s*(D\S+)\s+\S+\s+\S+\s+([^ =]+)\s*(\S+\s*=.*)?\s*$/i) {  ## diode
        my ($dioInstname, $dioType, $param) = ($1, $2, $3);
        if(!$param) { $param = "area=0 pj=0"; }  ## d_pwdnw_ckt, have no property, diode format "area:pj"
        push @{$hier->{$sktName}->{dio}}, "$dioInstname:$dioType:$param";
      }elsif(/^\s*(Q\S+)\s+.*\s+([^ =]+)\s+(\S+\s*=.*)\s*$/i) {  ## bjt
        my ($bjtInstname, $bjtType, $param) = ($1, $2, $3);
        push @{$hier->{$sktName}->{bjt}}, "$bjtInstname:$bjtType:$param";
      }elsif(/^\s*(C\S+)\s+.*\s+([^ =]+)\s+(\S+\s*=.*)\s*$/i) { ## cap
        my ($capInstname, $capType, $param) = ($1, $2, $3);
        push @{$hier->{$sktName}->{cap}}, "$capInstname:$capType:$param";
      }
    }elsif($sktFlag == 1 && /^\s*([XMRDQC]\S+)\s+/i && $sktName eq $topcell) {  ## inside top cell
      if(/^\s*(X\S+)\s+[^=]*?\s+([^ =]+)\s*(\S+\s*=.*)?\s*$/i) {
        my ($instName, $instancedCell, $param) = ($1,$2,$3);
        #print "$instName -- $instancedCell -- $param\n";##Maybe only one instance in topcell.
        #if($sktInfo->{$instancedCell}->{lib} eq "TECHLIB" && $param && $param =~ /W[NP]/i) {  ## like inv in stdcells_am/invLx1
        if($param && $param =~ /W[NP]\d*\s*=/i) {  ## like inv in stdcells_am/invLx1
          $bgate->{$sktName}->{$instName} = $param;
        }elsif($sktInfo->{$instancedCell}->{lib} eq "TECHLIB" && $param && $param =~ /l\s*=/i) {   ## 5T res: XI_RNPDIFF5t_3 net5 net4 A B vss! / RNPDIFF5t
          $resskt->{$sktName}->{$instName} = $param;
        }
        $topLevel->{$instName}->{cell}=$instancedCell;
        foreach my $searchedcell (@searchedcellList) {
          if(lc($instancedCell) eq lc($searchedcell)) {
            my $psum = "justkeyword";  ## no real meaning, just format compatibility
            devCountSummary($instName, "searchedcell", $instancedCell, $psum, $sktName, 1);
          }
        }
      }elsif(/^\s*(M\S+)\s+.*\s+([^ =]+)\s+(\S+\s*=.*)\s*$/i) {  ## mos in topcell
        my ($mosInstname, $mosType, $param) = ($1, $2, $3);
        #print "$mosInstname -- $mosType -- $param\n";
        my ($w,$l,$nf);
        $param =~ s/^/ /; $param =~ s/$/ /;
        if($param =~ /\sw\s*=\s*(\S+)/i) { $w = unitalign($1); }
        if($param =~ /\sl\s*=\s*(\S+)/i) { $l = unitalign($1); }
        if($param =~ /\snf\s*=\s*(\S+)/i) { $nf = unitalign($1); }
        my $psum = "${l}:${w}:$nf";
        devCountSummary($mosInstname, "mos", $mosType, $psum, $sktName, 1);
      }elsif(/^\s*(R\S+)\s+.*\s+([^ =]+)\s+(\S+\s*=.*)\s*$/i) {  ## res in topcell
        my ($resInstname, $resType, $param) = ($1, $2, $3);
        my ($w,$l,$nm,$n) = (0,0,0,0);
        $param =~ s/^/ /; $param =~ s/$/ /;
        if($param =~ /\sw\s*=\s*(\S+)/i) { $w = unitalign($1); }
        if($param =~ /\sl\s*=\s*(\S+)/i) { $l = unitalign($1); }
        if($param =~ /\snm\s*=\s*(\S+)/i) { $nm = unitalign($1); }
        if($param =~ /\sn\s*=\s*(\S+)/i) { $n = unitalign($1); }
        my $psum = "${l}:${w}:${nm}:$n";
        devCountSummary($resInstname, "res", $resType, $psum, $sktName, 1);
      }elsif(/^\s*(D\S+)\s+\S+\s+\S+\s+([^ =]+)\s*(\S+\s*=.*)?\s*$/i) {  ## diode in topcell
        my ($dioInstname, $dioType, $param) = ($1, $2, $3);       ## d_pwdnw_ckt have no property, eg: 'DDD1 vss! vtsc! d_pwdnw_ckt'
        my ($area,$pj) = (0,0);
        if($param) {
          $param =~ s/^/ /; $param =~ s/$/ /;
          if($param =~ /\sarea\s*=\s*(\S+)/i) { $area = unitalign($1)*1E6; }
          if($param =~ /\spj\s*=\s*(\S+)/i) { $pj = unitalign($1); }
        }
        my $psum = "${area}:$pj";
        devCountSummary($dioInstname, "dio", $dioType, $psum, $sktName, 1);
      }elsif(/^\s*(Q\S+)\s+.*\s+([^ =]+)\s+(\S+\s*=.*)\s*$/i) {  ## bjt in topcell
        my ($bjtInstname, $bjtType, $param) = ($1, $2, $3);
        my $area = 0;
        $param =~ s/^/ /; $param =~ s/$/ /;
        if($param =~ /\sarea\s*=\s*(\S+)/i) { $area = unitalign($1)*1E6; }
        my $psum = $area;
        devCountSummary($bjtInstname, "bjt", $bjtType, $psum, $sktName, 1);
      }elsif(/^\s*(C\S+)\s+.*\s+([^ =]+)\s+(\S+\s*=.*)\s*$/i) {  ## cap in topcell
        my ($capInstname, $capType, $param) = ($1, $2, $3);
        my ($nc, $nr) = (0, 0);
        $param =~ s/^/ /; $param =~ s/$/ /;
        if($param =~ /\snc\s*=\s*(\S+)/i) { $nc = $1; }
        if($param =~ /\snr\s*=\s*(\S+)/i) { $nr = $1; }
        my $psum = "${nc}:$nr";
        devCountSummary($capInstname, "cap", $capType, $psum, $sktName, 1);
      }
    }elsif($sktFlag == 1 && /^\s*\.ends/) {
      $sktFlag=0;
    }
  } # foreach
  return($hier)
}

sub unitalign {
  my ($p) = @_;
  if($p=~/u$/i) {
    $p=~s/u$//;
    $p=$p*1.0;
  }elsif($p=~/n$/i) {
    $p=~s/n$//;
    $p=$p*0.001;
  }elsif($p=~/E-/i) {
    $p=$p*1E6;
  }elsif($p=~/^[0-9.e]+$/) {
    $p=$p*1;
  }else{
    print "[ERROR]: cannot fingure unit of param - $p\n";
    exit 1;
  }
  return($p);
}

sub removePlusSymbol {
  my @noPlusContents;
  for(my $i=0; $i<=$#contents; $i++) {
    my $line=$contents[$i];
    chomp $line;
    my $next=$i+1;
    if($line =~ /^\s*\.subckt\s+\S+\s+/i) {
      my $sktFull=$line;
      while($contents[$next] =~ /^\s*\+/) {
        my $nextLine=$contents[$next];
        chomp $nextLine;
        $nextLine=~s/^\s*\+/ /;
        $sktFull.=$nextLine;
        $next++;
      }
      push @noPlusContents,$sktFull;
      next;
    }elsif($line =~ /^\s*[XMDRQ]\S+\s+/i && $next <= $#contents) {
      my $instFull=$line;
      while($contents[$next] =~ /^\s*\+/) {
        my $nextLine=$contents[$next];
        chomp $nextLine;
        $nextLine=~s/^\s*\+/ /;
        $instFull.=$nextLine;
        $next++;
        if($next > $#contents) { last; }
      }
      push @noPlusContents,$instFull;
      next;
    }elsif($line =~ /^\s*\+/) {
      next;
    }
    push @noPlusContents,$line;
  }

  ## debug
  open(TT, ">test");
  foreach (@noPlusContents) {
    print TT $_,"\n";
  }
  close TT;
    
  return(@noPlusContents);
}

sub Get_hierpath_and_inst {
  my ($path) = @_;
  my ($hp, $inst);
  if($path =~ /\./ && $path =~ /^(.*)\.([^\.]+$)/) {
    ($hp, $inst) = ($1, $2);
  }else{  ## in top cell, like 'MN0' directly
    $hp = "";
    $inst = $path;
  }
  return($hp, $inst);
}
