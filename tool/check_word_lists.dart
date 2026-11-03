// Checks a folder of plain-text word lists and prints per-file counts.
//
//   dart run tool/check_word_lists.dart dist
//
// Warnings point at a file and line number only; the entries themselves are
// never printed, so this is safe to run in a terminal that records history or
// in CI logs.
import 'dart:io';

import 'package:safe_text/safe_text.dart';

Future<void> main(List<String> args) async {
  final source = args.isEmpty ? 'dist' : args.first;
  stdout.writeln('Reading word lists from: $source');

  try {
    final import = await loadWordLists(source);

    stdout.writeln(import);
    for (final file in import.files) {
      stdout.writeln('  $file (${file.duplicates} duplicate line(s))');
    }
    for (final warning in import.warnings) {
      stdout.writeln('  warning: $warning');
    }

    if (import.isEmpty) {
      stderr.writeln('No entries were imported.');
      exitCode = 1;
    }
  } on WordListFormatException catch (error) {
    final where = error.source == null ? '' : ' (${error.source})';
    stderr.writeln('Could not read the word lists: ${error.message}$where');
    exitCode = 1;
  }
}
