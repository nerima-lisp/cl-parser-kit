#!/usr/bin/env perl

use strict;
use warnings;
use Cwd qw(abs_path);

my ($report, $source_directory, $expression_threshold, $branch_threshold) = @ARGV;
die "usage: $0 REPORT SOURCE_DIRECTORY EXPRESSION_THRESHOLD BRANCH_THRESHOLD\n"
  unless defined $branch_threshold;

open my $handle, '<', $report or die "cannot read $report: $!\n";
local $/;
my $html = <$handle>;
close $handle or die "cannot close $report: $!\n";

$source_directory = abs_path($source_directory)
  // die "cannot resolve source directory $source_directory\n";
$source_directory =~ s{/*$}{/};
my %counts = (
  expression => [0, 0],
  branch => [0, 0],
);
my %adjusted_counts = (
  expression => [0, 0],
  branch => [0, 0],
);
my $current_directory = '';

# SB-COVER attributes a macro's generated code to its call site, never to the
# macro's own definition, so a file whose only content is a macro definition
# (plus helpers used solely by that macro) reads as permanently 0% covered no
# matter how thoroughly the code it generates is tested elsewhere -- verified
# for these files by reading their content and confirming every generated
# function has dedicated call-site tests (see docs/src/development.md, "Coverage
# Expectations"). ADJUSTED-* below excludes exactly these files from the
# denominator so the reported percentage reflects instrumentable code only;
# the gate itself still runs against the raw, unadjusted totals.
my %macro_attribution_artifact_files = map { $_ => 1 } (
  'tree-macros.lisp',
  'package.lisp',
  'pratt.lisp',
);

while ($html =~ m{
  <tr\s+class='subheading'><td\s+colspan='7'>([^<]+)</td></tr>
  |
  <tr\s+class='(?:odd|even)'>
    <td\s+class='text-cell'><a\s+href='[^']+'>([^<]+)</a></td>
    <td>(\d+|-)</td><td>(\d+|-)</td><td>[^<]+</td>
    <td>(\d+|-)</td><td>(\d+|-)</td><td>[^<]+</td>
  </tr>
}gx) {
  if (defined $1) {
    $current_directory = $1;
    next;
  }
  next unless index($current_directory, $source_directory) == 0;

  my $filename = $2;
  my @values = ($3, $4, $5, $6);
  for my $value (@values) {
    $value = 0 if $value eq '-';
  }
  $counts{expression}[0] += $values[0];
  $counts{expression}[1] += $values[1];
  $counts{branch}[0] += $values[2];
  $counts{branch}[1] += $values[3];

  next if $macro_attribution_artifact_files{$filename};
  $adjusted_counts{expression}[0] += $values[0];
  $adjusted_counts{expression}[1] += $values[1];
  $adjusted_counts{branch}[0] += $values[2];
  $adjusted_counts{branch}[1] += $values[3];
}

my %thresholds = (
  expression => $expression_threshold,
  branch => $branch_threshold,
);
my @failures;
for my $kind (qw(expression branch)) {
  my ($covered, $total) = @{$counts{$kind}};
  die "no $kind coverage data found below $source_directory\n" unless $total;
  my $percent = 100 * $covered / $total;
  printf "%s coverage: %d/%d (%.2f%%), required: %.2f%%\n",
    $kind, $covered, $total, $percent, $thresholds{$kind};
  push @failures, "$kind coverage is below $thresholds{$kind}%"
    if $percent < $thresholds{$kind};

  my ($adjusted_covered, $adjusted_total) = @{$adjusted_counts{$kind}};
  die "macro-attribution exclusion list covers every file with $kind data below "
      . "$source_directory -- %macro_attribution_artifact_files is too broad; "
      . "only exclude a file when its own gap, not the whole codebase's, is "
      . "confirmed artifact\n"
    unless $adjusted_total;
  my $adjusted_percent = 100 * $adjusted_covered / $adjusted_total;
  printf "%s coverage (macro-attribution files excluded): %d/%d (%.2f%%)\n",
    $kind, $adjusted_covered, $adjusted_total, $adjusted_percent;
}

die join("\n", @failures), "\n" if @failures;
