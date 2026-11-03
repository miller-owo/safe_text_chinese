import 'dart:convert';
import 'dart:io';

import 'models/language.dart';
import 'safe_text_filter.dart';
import 'word_list_import.dart';

/// Reads plain-text word lists from disk and merges them into a
/// [WordListImport].
///
/// [source] can be a directory (every `*.txt` file directly inside it is read,
/// in name order), a single file, a glob pattern such as `dist/*.txt`, or a
/// list mixing those. This is the "one entry per line" format described in
/// [WordListParser].
///
/// ```dart
/// final import = await loadWordLists('dist');
/// if (import.isEmpty) {
///   print('No word lists found');
/// } else {
///   print(import); // WordListImport(3 files, 1234 words)
///   SafeTextFilter.init(
///     language: Language.chinese,
///     additionalWords: import.words,
///   );
/// }
/// ```
///
/// Files are decoded as UTF-8; a byte-order mark is dropped and invalid UTF-8
/// raises a [WordListFormatException] that names the file instead of silently
/// importing mojibake (a list saved as GBK will fail this way — re-save it as
/// UTF-8).
///
/// Set `includeBundledWords` on `SafeTextFilter.init` to `false` to run on the
/// imported list alone, or use [initFromWordLists] to do both steps at once.
///
/// Not available on the web, where there is no file system: load the text
/// yourself and use [WordListImport.merge] instead.
Future<WordListImport> loadWordLists(
  Object source, {
  String extension = '.txt',
  bool recursive = false,
  bool allowInlineComments = true,
  int maxEntryRunes = 64,
}) async {
  final files = _resolveFiles(source, extension, recursive);

  if (files.isEmpty) {
    return WordListImport(
      words: const [],
      warnings: [
        'No $extension files found in ${_describe(source)}',
      ],
    );
  }

  final texts = <String, String>{};
  for (final file in files) {
    texts[file.path] = await _readUtf8(file);
  }

  return WordListImport.merge(
    texts,
    allowInlineComments: allowInlineComments,
    maxEntryRunes: maxEntryRunes,
  );
}

/// Reads every word list under [source] and initializes [SafeTextFilter] with
/// them, in one call.
///
/// This is [loadWordLists] followed by `SafeTextFilter.init`, so a folder of
/// `AAA.txt`, `BBB.txt`, `CCC.txt`, … is blocked with a single line:
///
/// ```dart
/// // Your import plus the bundled English list — the default:
/// final import = await initFromWordLists('dist');
///
/// // Or another bundled list:
/// final import = await initFromWordLists('dist', language: Language.chinese);
///
/// // Or your import alone:
/// final import = await initFromWordLists('dist', includeBundledWords: false);
/// ```
///
/// With no [language] or [languages] the bundled list is
/// [Language.english], matching `SafeTextFilter.init`.
///
/// Returns the [WordListImport], so the caller can log the counts or check
/// `isEmpty` before relying on the filter. An empty import does not throw: the
/// filter is only as good as the files it found.
///
/// Not available on the web; see [WordListImport.merge].
Future<WordListImport> initFromWordLists(
  Object source, {
  Language? language,
  List<Language>? languages,
  bool includeBundledWords = true,
  String extension = '.txt',
  bool recursive = false,
  bool allowInlineComments = true,
}) async {
  final import = await loadWordLists(
    source,
    extension: extension,
    recursive: recursive,
    allowInlineComments: allowInlineComments,
  );

  SafeTextFilter.init(
    language: language,
    languages: languages,
    additionalWords: import.words,
    includeBundledWords: includeBundledWords,
  );

  return import;
}

Future<String> _readUtf8(File file) async {
  final List<int> bytes;
  try {
    bytes = await file.readAsBytes();
  } on FileSystemException catch (error) {
    throw WordListFormatException(
      'Could not read the file: ${error.message}',
      source: file.path,
    );
  }

  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw WordListFormatException(
      'The file is not valid UTF-8 text. Save the word list as UTF-8 '
      '(a byte-order mark is fine).',
      source: file.path,
    );
  }
}

List<File> _resolveFiles(Object source, String extension, bool recursive) {
  final inputs = source is Iterable ? source.toList() : <Object>[source];
  final files = <File>[];
  final seen = <String>{};

  void add(File file) {
    if (seen.add(file.path)) files.add(file);
  }

  for (final input in inputs) {
    if (input is Directory) {
      _addDirectory(input, extension, recursive, add);
    } else if (input is File) {
      if (!input.existsSync()) {
        throw WordListFormatException('File not found.', source: input.path);
      }
      add(input);
    } else if (input is String) {
      final wildcard = _wildcardPattern(input);
      if (wildcard != null) {
        _addMatches(wildcard, add);
        continue;
      }

      switch (FileSystemEntity.typeSync(input)) {
        case FileSystemEntityType.directory:
          _addDirectory(Directory(input), extension, recursive, add);
        case FileSystemEntityType.file:
          add(File(input));
        case FileSystemEntityType.link:
          add(File(input));
        default:
          throw WordListFormatException(
            'Path not found. Pass a directory such as "dist", a .txt file, or '
            'a pattern such as "dist/*.txt".',
            source: input,
          );
      }
    } else {
      throw ArgumentError.value(
        input,
        'source',
        'Expected a String path, a Directory, a File, or a list of those',
      );
    }
  }

  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

void _addDirectory(
  Directory directory,
  String extension,
  bool recursive,
  void Function(File) add,
) {
  if (!directory.existsSync()) {
    throw WordListFormatException(
      'Directory not found.',
      source: directory.path,
    );
  }
  for (final entity in directory.listSync(
    recursive: recursive,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    if (!_hasExtension(entity.path, extension)) continue;
    add(entity);
  }
}

void _addMatches(_Wildcard wildcard, void Function(File) add) {
  final directory = Directory(wildcard.directory);
  if (!directory.existsSync()) {
    throw WordListFormatException(
      'Directory not found.',
      source: wildcard.directory,
    );
  }
  final matcher = RegExp(wildcard.pattern, caseSensitive: false);
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is! File) continue;
    if (!matcher.hasMatch(_basename(entity.path))) continue;
    add(entity);
  }
}

bool _hasExtension(String path, String extension) =>
    path.toLowerCase().endsWith(extension.toLowerCase());

String _basename(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf(r'\');
  final index = slash > backslash ? slash : backslash;
  return index < 0 ? path : path.substring(index + 1);
}

/// A `dist/*.txt` style pattern, split into the directory to scan and a regular
/// expression to match the file name against.
class _Wildcard {
  const _Wildcard(this.directory, this.pattern);

  final String directory;
  final String pattern;
}

_Wildcard? _wildcardPattern(String path) {
  final separator = path.lastIndexOf(RegExp(r'[\\/]'));
  final name = separator < 0 ? path : path.substring(separator + 1);
  if (!name.contains('*') && !name.contains('?')) return null;

  final directory = separator < 0 ? '.' : path.substring(0, separator);
  final pattern = StringBuffer('^');
  for (final rune in name.runes) {
    if (rune == 0x2A) {
      pattern.write('.*'); // *
    } else if (rune == 0x3F) {
      pattern.write('.'); // ?
    } else {
      pattern.write(RegExp.escape(String.fromCharCode(rune)));
    }
  }
  pattern.write(r'$');

  return _Wildcard(directory.isEmpty ? '.' : directory, pattern.toString());
}

String _describe(Object source) {
  if (source is FileSystemEntity) return source.path;
  if (source is Iterable) {
    return source.map((Object? item) => _describe(item ?? 'null')).join(', ');
  }
  return '$source';
}
