# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-18

First release.

### Added

- `glosa::parse [--version <v>] <help> [args...]`: a source mode that assigns
  variables directly, with no subprocesses.
- `glosa [--version <v>] -h <help> : [args...]`: a CLI mode that prints
  shell code for `eval`. Every value is quoted with `printf %q`.
- Usage syntax:
  - required and optional positionals (`<x>`, `[<x>]`, `FILE`) and commands;
  - several usage lines;
  - groups `( )` and `[ ]` with alternatives `|`;
  - repetition `...`;
  - the `[options]` shortcut;
  - `--`.
- Options:
  - short and long aliases declared in any `*options:` section;
  - values (`--out=<f>`, `--out <f>`, `-o<f>`, `-o <f>`) with `[default: …]`;
  - stacked short flags;
  - counters (`-v...`) and repeated values (`--file=<f>...`) as arrays;
  - unique prefixes of long options.
- `-h`/`--help` (and `--version` when configured) as the first argument
  print the help (or version) and exit 0.
- Usage errors print a message and the `Usage:` block to stderr and exit 1.
  An invalid help text exits 2 with `glosa: invalid help text: …`.
- Every declared variable is always defined, so scripts can use `set -u`.
- The caller's `set -e`, `set -u`, `set -f`, `IFS`, `nocasematch` and
  locale are preserved.
- Works on Bash 3.2 through 5.x. Tested on macOS and Linux.

[Unreleased]: https://github.com/DavidMRGaona/glosa/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/DavidMRGaona/glosa/releases/tag/v0.1.0
