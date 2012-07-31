#!/usr/bin/perl -w
#
# Copyright (C) 2012 Intel Corporation
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#   Authors:
#
#          Wendong,Sui  <weidongx.sun@intel.com>
#          Tao,Lin  <taox.lin@intel.com>
#
#

package TestLog;
use strict;
use Packages;
use Common;
use File::Find;
use FindBin;
use Data::Dumper;

# Export symbols
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(
  &writeResultInfo
);

# where is the result home folder
my $result_dir_manager = $FindBin::Bin . "/../../results/";
my $defination_dir     = $FindBin::Bin . "/../../defination/";
my $result_dir_lite    = $FindBin::Bin . "/../../lite";

# save time -> package_name -> package_dir
my @time_package_dir = ();
my $time             = "none";
my $isOnlyAuto       = "FALSE";
my $total            = 0;         # total case number from txt file
my @targetFilter;
my $dir_root     = "none";
my $combined_xml = "none";
my $combined_txt = "none";

sub writeResultInfo {
	my ( $time_only, $isOnlyAuto_temp, @targetFilter_temp ) = @_;
	$isOnlyAuto   = $isOnlyAuto_temp;
	@targetFilter = @targetFilter_temp;

	syncDefination();

	if ( $time_only ne "" ) {
		find( \&changeDirStructure_wanted,
			$result_dir_lite . "/" . $time_only );
		find( \&writeResultInfo_wanted, $result_dir_lite . "/" . $time_only );
	}
	else {
		find( \&changeDirStructure_wanted, $result_dir_lite );
		find( \&writeResultInfo_wanted,    $result_dir_lite );
	}

	# add WRITE at the bottom, remove WRITE from beginning
	push( @time_package_dir, "WRITE" );
	shift(@time_package_dir);

	my $package_verdict = "none";

	# write info to file
	my $count = 0;
	while ( $count < @time_package_dir ) {
		my $temp = $time_package_dir[$count];
		if ( $temp eq "WRITE" ) {
			my $info = <<DATA;
Time:$time
$package_verdict
DATA

			# write info
			write_string_as_file( $result_dir_manager . $time . "/info",
				$info );

			# write runconfig
			writeRunconfig($time);

			# create tar file
			my $tar_cmd_delete =
			  "rm -f " . $result_dir_manager . $time . "/*.tgz";
			my $tar_cmd_create =
			    "tar -czPf "
			  . $result_dir_manager
			  . $time . "/"
			  . $time . ".tgz "
			  . $result_dir_manager
			  . $time . "/*";
			system("$tar_cmd_delete");
			system("$tar_cmd_create &>/dev/null");

			$time            = "none";
			$package_verdict = "none";
		}
		elsif ( $temp =~ /^[0-9:\.\-]+$/ ) {
			$time = $temp;
		}
		elsif ( $temp =~ /^[\w\d\-]+$/ ) {
			if ( $package_verdict eq "none" ) {
				$package_verdict = "Package:" . $temp . "\n";
			}
			else {
				$package_verdict .= "\nPackage:" . $temp . "\n";
			}
			for ( my $i = 1 ; $i <= 8 ; $i++ ) {
				$package_verdict .= $time_package_dir[ ++$count ] . "\n";
			}
			$package_verdict .= $time_package_dir[ ++$count ];
		}
		$count++;
	}
}

sub writeResultInfo_wanted {
	my $dir = $File::Find::name;
	if ( $dir =~ /$result_dir_lite\/([0-9:\.\-]+)$/ ) {
		push( @time_package_dir, "WRITE" );
		push( @time_package_dir, $1 );
		$time = $1;
		my $mkdir_path = $result_dir_manager . $1;
		system("mkdir -p $mkdir_path");
	}
	if (   ( $dir =~ /.*\/[0-9:\.\-]+\/usr\/share\/([\w\d\-]+)$/ )
		or ( $dir =~ /.*\/[0-9:\.\-]+\/usr\/local\/share\/([\w\d\-]+)$/ ) )
	{
		my $package_name = $1;
		if ( -e $dir . "/tests.result.txt" ) {
			system( 'mv ' . $dir . "/tests.result.txt " . $dir . "/tests.txt" );
			my $testkit_lite_result_txt = $dir . "/tests.txt";
			system( "cp $testkit_lite_result_txt $result_dir_manager$time"
				  . "/$package_name"
				  . "_tests.txt" );

		}
		if ( -e $dir . "/tests.result.xml" ) {
			system( 'mv ' . $dir . "/tests.result.xml " . $dir . "/tests.xml" );
			my $testkit_lite_result_xml = $dir . "/tests.xml";
			system( "cp $testkit_lite_result_xml $result_dir_manager$time"
				  . "/$package_name"
				  . "_tests.xml" );
		}
		my $txt_result = $dir . "/tests.txt";
		my $xml_result = $dir . "/tests.xml";

		my $startCase          = "FALSE";
		my @xml                = ();
		my $manual_case_number = 0;

		# if dir is not empty, create manual case list
		if (
			   ( -e $txt_result )
			&& ( -e $xml_result )
			&& !(
				  -e $result_dir_manager 
				. $time . "/"
				. $package_name
				. "_manual_case_tests.txt"
			)
		  )
		{

			# get all manual cases
			my $content      = "";
			my $suite_name   = "";
			my $set_name     = "";
			my $case_content = "";
			my $test_definition_xml =
			  $defination_dir . $package_name . "/tests.xml";
			open FILE, $test_definition_xml
			  or die "can't open " . $test_definition_xml;
			system( 'cp '
				  . $test_definition_xml . ' '
				  . $result_dir_manager
				  . $time . '/'
				  . $package_name
				  . '_definition.xml' );

			while (<FILE>) {
				if ( $_ =~ /suite.*name="(.*?)".*/ ) {
					push( @xml, $_ );
					chomp( $suite_name = $_ );
				}
				if ( $_ =~ /<\/suite>/ ) {
					push( @xml, $_ );
				}
				if ( $_ =~ /set.*name="(.*?)".*/ ) {
					push( @xml, $_ );
					chomp( $set_name = $_ );
				}
				if ( $_ =~ /<\/set>/ ) {
					push( @xml, $_ );
				}
				if ( $startCase eq "TRUE" ) {
					push( @xml, $_ );
				}
				if (   ( $_ =~ /.*<testcase.*execution_type="manual".*/ )
					&& ( $isOnlyAuto eq "FALSE" ) )
				{
					chomp( $case_content = $_ );
					my $allMatch = "TRUE";
					my $xml_single_case =
					  $suite_name . $set_name . $case_content;
					foreach (@targetFilter) {
						chomp( my $filter = $_ );
						if ( $xml_single_case !~ /$filter/ ) {
							$allMatch = "FALSE";
						}
					}
					if ( $allMatch eq "TRUE" ) {
						$manual_case_number++;
						$startCase = "TRUE";
						push( @xml, $_ );
						if ( $_ =~ /.*<testcase.*id="(.*?)".*/ ) {
							my $temp_id = $1;
							my $auto_case_result_xml =
							    $result_dir_manager 
							  . $time . '/'
							  . $package_name
							  . '_tests.xml';
							my $name = $temp_id;
							$name =~ s/\s/\\ /g;
							my $cmd_getLine =
							    'grep id=\\"' 
							  . $name . '\\" '
							  . $auto_case_result_xml . ' -n';
							my $grepResult = `$cmd_getLine`;
							if ( $grepResult =~ /\s*(\d*)\s*:(.*>)/ ) {
								my $line_number  = $1;
								my $line_content = $2;
								if ( $line_content =~ /result="(.*)"/ ) {
									my $result = $1;
									$content .= $temp_id . ":$result\n";
								}
								else {
									$content .= $temp_id . ":N/A\n";
								}
							}
							else {
								$content .= $temp_id . ":N/A\n";
							}
						}
					}
				}
				if ( $_ =~ /.*<\/testcase>.*/ ) {
					$startCase = "FALSE";
				}
			}
			my $file_list;
			open $file_list,
			    ">"
			  . $result_dir_manager
			  . $time . "/"
			  . $package_name
			  . "_manual_case_tests.txt"
			  or die $!;
			print {$file_list} $content;
			close $file_list;
		}

		#don't write if no manual case
		if ( @xml > 1 ) {

			# write manual cases' xml to a xml
			my $file_xml;
			open $file_xml,
			    ">"
			  . $result_dir_manager
			  . $time . "/"
			  . $package_name
			  . "_manual_case_tests.xml"
			  or die $!;
			foreach (@xml) {
				print {$file_xml} $_;
			}
			close $file_xml;
		}

		# get result info
		my @totalVerdict =
		  getTotalVerdict( $dir, $time, $package_name, $manual_case_number );
		my @verdict = getVerdict( $dir, $time, $package_name );
		if ( ( @totalVerdict == 3 ) && ( @verdict == 6 ) ) {
			push( @time_package_dir, $package_name );
			for ( my $i = 1 ; $i <= 3 ; $i++ ) {
				push( @time_package_dir, shift(@totalVerdict) );
			}
			for ( my $i = 1 ; $i <= 6 ; $i++ ) {
				push( @time_package_dir, shift(@verdict) );
			}
		}
	}
}

# parse tests_result.txt and get total, pass, fail number
sub getTotalVerdict {
	my ( $testkit_lite_result, $time, $package, $manual_case_number ) = @_;
	my $testkit_lite_result_txt = $testkit_lite_result . "/tests.txt";

	# parse tests_result.txt
	my @totalVerdict = ();
	if ( -e $testkit_lite_result_txt ) {
		open FILE, $testkit_lite_result_txt or die $!;
		while (<FILE>) {
			if (   ( $_ =~ /.*tests.xml\s*XML\s*(\d+)\s*(\d+)\s*(\d+)\s*/ )
				or
				( $_ =~ /.*tests.result.xml\s*XML\s*(\d+)\s*(\d+)\s*(\d+)\s*/ )
			  )
			{
				$total = int($1) + int($2) + int($3);
				push( @totalVerdict, "Total:" . $total );
				push( @totalVerdict, "Pass:" . $1 );
				push( @totalVerdict, "Fail:" . $2 );
			}
		}
	}
	return @totalVerdict;
}

# parse tests_result.xml and get total, pass, fail number for both manual and auto cases
sub getVerdict {
	my ( $testkit_lite_result, $time, $package ) = @_;
	my $testkit_lite_result_xml = $testkit_lite_result . "/tests.xml";
	my $manual_result_list =
	  $result_dir_manager . $time . "/" . $package . "_manual_case_tests.txt";

	# parse tests_result.xml
	my @verdict = ();
	if ( ( -e $testkit_lite_result_xml ) && ( -e $manual_result_list ) ) {
		my $totalM = 0;
		my $passM  = 0;
		my $failM  = 0;
		my $totalA = 0;
		my $passA  = 0;
		my $failA  = 0;

		open FILE, $manual_result_list or die $!;
		while (<FILE>) {
			if ( $_ =~ /PASS/ ) {
				$passM += 1;
			}
			if ( $_ =~ /FAIL/ ) {
				$failM += 1;
			}
			$totalM += 1;
		}
		push( @verdict, "Total(M):" . $totalM );
		push( @verdict, "Pass(M):" . $passM );
		push( @verdict, "Fail(M):" . $failM );

		open FILE, $testkit_lite_result_xml or die $!;
		while (<FILE>) {

			# just count auto case
			if ( $_ =~ /.*<testcase.*execution_type="auto".*/ ) {
				$totalA += 1;
				if ( $_ =~ /.*result="PASS".*/ ) {
					$passA += 1;
				}
				elsif ( $_ =~ /.*result="FAIL".*/ ) {
					$failA += 1;
				}
			}
		}
		if ( $totalA == 0 ) {
			$totalA = $total - $totalM;
		}
		push( @verdict, "Total(A):" . $totalA );
		push( @verdict, "Pass(A):" . $passA );
		push( @verdict, "Fail(A):" . $failA );
	}
	return @verdict;
}

sub writeRunconfig {
	my ($time) = @_;
	chomp( my $hardware_platform = `uname -i` );
	chomp( my $package_manager   = guess_package_manager( detect_OS() ) );
	chomp( my $username          = `w | sed -n '3,3p' | cut -d ' ' -f 1` );
	chomp( my $hostname          = `uname -n` );
	chomp( my $kernel            = `uname -r` );
	chomp( my $operation_system  = `uname -o` );

	my $runconfig = <<DATA;
Hardware Platform:$hardware_platform
Package Manager:$package_manager
Username:$username
Hostname:$hostname
Kernel:$kernel
Operation System:$operation_system
DATA
	write_string_as_file( $result_dir_manager . $time . "/runconfig",
		$runconfig );
}

sub changeDirStructure_wanted {
	my $dir = $File::Find::name;
	if ( $dir =~ /.*\/([0-9:\.\-]+)$/ ) {
		if ( $dir !~ /[0-9:\.\-]+\/opt/ ) {
			my $time = $1;
			$combined_xml = "none";
			$combined_txt = "none";
			find( \&findXmlTxt_wanted, $result_dir_lite . "/" . $time );
			if ( ( $combined_xml ne "none" ) && ( $combined_txt ne "none" ) ) {
				$dir_root = $result_dir_lite . "/" . $time;
				rewriteXmlFile($combined_xml);
				rewriteTxtFile($combined_txt);
			}
		}
	}
}

sub findXmlTxt_wanted {
	my $dir = $File::Find::name;
	if (   ( $dir =~ /tests\..{6}\.result\.xml/ )
		or ( $dir =~ /tests\.result\.xml/ ) )
	{
		$combined_xml = $dir;
	}
	if (   ( $dir =~ /tests\..{6}\.result\.txt/ )
		or ( $dir =~ /tests\.result\.txt/ ) )
	{
		$combined_txt = $dir;
	}
}

sub rewriteTxtFile {
	my ($combined_txt) = @_;
	open FILE, $combined_txt
	  or die "can't open " . $combined_txt;
	my $title        = "none";
	my $content      = "none";
	my $package_name = "none";
	while (<FILE>) {
		if ( $_ =~ /TestReport/ ) {
			$title = $_;
		}
		if ( $_ =~ /TYPE\s*PASS\s*FAIL\s*N\/A/ ) {
			$title .= "\n" . $_;
		}
		if ( $_ =~ /---(.*)\s*SUITE\s*(\d+)\s*(\d+)\s*(\d+)\s*/ ) {
			$package_name = $1;
			$package_name =~ s/^\s*//;
			$package_name =~ s/\s*$//;
			$content = $title . $_;
			my $package_name_dec = $package_name . "/tests.result.xml";
			$content =~ s/$package_name/$package_name_dec/;
			$content =~ s/\s{15}SUITE/XML/;
			writeTxtResult( $package_name, $content );
		}
	}
}

sub rewriteXmlFile {
	my ($combined_xml) = @_;
	open FILE, $combined_xml
	  or die "can't open " . $combined_xml;
	my $need_manual_carriage_return = "FALSE";
	while (<FILE>) {
		if ( $_ =~ /<\/suite><\/test_definition>/ ) {
			$need_manual_carriage_return = "TRUE";
		}
	}
	open FILE, $combined_xml
	  or die "can't open " . $combined_xml;
	my $content      = "none";
	my $package_name = "none";
	while (<FILE>) {
		if ( $need_manual_carriage_return eq "TRUE" ) {
			if ( $_ =~ /<suite name="(.*?)">/ ) {

			# get the start part of the result, and get the initial package name
				if ( $_ =~
					/.*<test_definition name=".*?">(<suite name=".*?">.*)/ )
				{
					$content = $1;
					if ( $_ =~ /<suite name="(.*?)">/ ) {
						$package_name = $1;
					}
				}

				# get the middle part of the result
				if ( $_ =~ /(.*<\/suite>)<suite name=".*?">.*/ ) {
					$content .= "\n" . $1;
					mkdirWriteXmlResult( $package_name, $content,
						$need_manual_carriage_return );
					if ( $_ =~ /<suite name="(.*?)">/ ) {
						$package_name = $1;
					}
				}
			}

			# get the end part of the result
			elsif ( $_ =~ /(.*<\/suite>)<\/test_definition>.*/ ) {
				$content .= "\n" . $1;
				mkdirWriteXmlResult( $package_name, $content,
					$need_manual_carriage_return );
			}
			else {
				$content .= "\n" . $_;
			}
		}
		else {
			if ( $_ =~ /<suite name="(.*?)">/ ) {
				$package_name = $1;

				# get first package name
				if ( $_ =~
					/.*<test_definition name=".*?">(<suite name=".*?">.*)/ )
				{
					$content = $1 . "\n";
				}

				# get package name in the middle
				else {
					$content = $_;
				}
			}

			# write to file for every end of a suite
			elsif ( $_ =~ /<\/suite>/ ) {
				$content .= $_;
				mkdirWriteXmlResult( $package_name, $content,
					$need_manual_carriage_return );
			}
			else {
				$content .= $_;
			}
		}
	}
}

sub mkdirWriteXmlResult {
	my ( $package_name, $content, $need_manual_carriage_return ) = @_;
	my @carriage_list = (
		'<suite.*?>',           '</suite>',
		'<set.*?>',             '</set>',
		'<testcase.*?>',        '</testcase>',
		'<description>',        '</description>',
		'<notes\s*/>',          '</notes>',
		'<pre_condition\s*/>',  '</pre_condition>',
		'<post_condition\s*/>', '</post_condition>',
		'<steps>',              '</steps>',
		'<step order.*?>',      '</step>',
		'</step_desc>',         '</expected>',
		'</test_script_entry>', '<result_info>',
		'</result_info>',       '<actual_result\s*/>',
		'</actual_result>',     '<start\s*/>',
		'</start>',             '<end\s*/>',
		'</end>',               '<stdout\s*/>',
		'</stdout>',            '<stderr\s*/>',
		'</stderr>',            '<categories\s*/>',
		'<categories>',         '</categories>',
		'</category>',          '<spec\s*/>',
		'</spec>'
	);
	foreach (@carriage_list) {

		# add carriage return manually, use it when it has -o option
		if ( $need_manual_carriage_return eq "TRUE" ) {
			$content =~ s/($_)/$1\n/g;
		}
	}

	# make dir to write result
	if ( !( -e $dir_root . "/usr/share/" . $package_name ) ) {
		system( "mkdir -p " . $dir_root . "/usr/share/" . $package_name );
	}
	else {
		system( "rm -rf " . $dir_root . "/usr/share/" . $package_name );
		system( "mkdir -p " . $dir_root . "/usr/share/" . $package_name );
	}

	# write to file
	my $file;
	open $file,
	  ">" . $dir_root . "/usr/share/" . $package_name . "/tests.result.xml"
	  or die "Failed to open file "
	  . $dir_root
	  . "/usr/share/"
	  . $package_name
	  . "/tests.result.xml for writing: $!";
	print {$file} $content;
	close $file;
}

sub writeTxtResult {
	my ( $package_name, $content ) = @_;

	my $file;
	open $file,
	  ">" . $dir_root . "/usr/share/" . $package_name . "/tests.result.txt"
	  or die "Failed to open file "
	  . $dir_root
	  . "/usr/share/"
	  . $package_name
	  . "/tests.result.txt for writing: $!";
	print {$file} $content;
	close $file;
}

sub syncDefination {
	system( "rm -rf $defination_dir" . "*" );
	my $cmd_defination = "sdb shell ls /usr/share/*/tests.xml";
	my @definations    = `$cmd_defination`;
	foreach (@definations) {
		my $defination = "";
		if ( $_ =~ /(\/usr\/share\/.*\/tests.xml)/ ) {
			$defination = $1;
		}
		$defination =~ s/\s*$//;
		if ( $defination =~ /share\/(.*)\/tests.xml/ ) {
			my $package_name = $1;
			system("mkdir $defination_dir$package_name");
			system( "sdb pull $defination $defination_dir$package_name" );
		}
	}
}

1;
