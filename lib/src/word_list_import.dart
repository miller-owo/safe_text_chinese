/// Reading, validating and merging plain-text word lists.
///
/// A word list is a UTF-8 text file with one entry per line:
///
/// ```text
/// # lines starting with # or // are comments
/// AAA
/// BBB
/// CCC  # an inline comment after whitespace is dropped too
/// ```
///
/// Blank lines are ignored, the entries are trimmed, duplicates are removed
/// (case-insensitively) and a UTF-8 byte-order mark is skipped.
///
/// Nothing here touches the file system, so it works on every platform,
/// including the web. To read `dist/*.txt` from disk use `loadWordLists` from
/// `package:safe_text/safe_text.dart`, which is only available where `dart:io`
/// is.
library;

import 'dart:convert';

/// Thrown when a word list cannot be read as text.
///
/// The [message] never contains an entry from the list, only the reason and,
/// where it helps, a line number.
class WordListFormatException extends FormatException {
  WordListFormatException(String message, {String? source})
      : super(message, source);
}

/// The result of parsing one word list.
class WordListParseResult {
  const WordListParseResult({
    required this.words,
    required this.lines,
    required this.duplicates,
    required this.warnings,
  });

  /// The entries in file order, without duplicates.
  final List<String> words;

  /// How many data lines the list had, duplicates included.
  final int lines;

  /// How many data lines repeated an entry seen earlier in the same list.
  final int duplicates;

  /// Human-readable problems. They point at a line number and never quote the
  /// entry itself.
  final List<String> warnings;

  /// The number of unique entries.
  int get count => words.length;
}

/// Parses one word list from its text form.
class WordListParser {
  /// Parses [content] as a word list.
  ///
  /// [source] is only used in warnings, e.g. the file name.
  ///
  /// When [allowInlineComments] is true (the default), a `#` or `//` that
  /// follows whitespace starts a comment and the rest of the line is dropped;
  /// `c#` and `http://…` are therefore left alone. Entries longer than
  /// [maxEntryRunes] are kept but reported, since a line that long is usually a
  /// mistake in the file.
  static WordListParseResult parse(
    String content, {
    String source = '<text>',
    bool allowInlineComments = true,
    int maxEntryRunes = 64,
  }) {
    final words = <String>[];
    final warnings = <String>[];
    final seen = <String>{};
    var lines = 0;
    var duplicates = 0;
    var lineNumber = 0;

    for (final rawLine in const LineSplitter().convert(_stripBom(content))) {
      lineNumber++;

      var line = rawLine.trim();
      if (line.isEmpty || _isFullLineComment(line)) continue;

      if (allowInlineComments) {
        line = _stripInlineComment(line);
        if (line.isEmpty) continue;
      }

      lines++;
      if (line.runes.length > maxEntryRunes) {
        warnings.add('$source:$lineNumber: entry is ${line.runes.length} '
            'characters long (limit $maxEntryRunes); kept as written');
      }

      if (!seen.add(line.toLowerCase())) {
        duplicates++;
        continue;
      }
      words.add(line);
    }

    return WordListParseResult(
      words: List.unmodifiable(words),
      lines: lines,
      duplicates: duplicates,
      warnings: List.unmodifiable(warnings),
    );
  }

  static String _stripBom(String text) =>
      text.startsWith('\uFEFF') ? text.substring(1) : text;

  static bool _isFullLineComment(String line) =>
      line.startsWith('#') || line.startsWith('//');

  /// Cuts a trailing `# …` or `// …` comment, which has to be preceded by
  /// whitespace so that entries containing `#` or `/` survive.
  static String _stripInlineComment(String line) {
    for (var i = 1; i < line.length; i++) {
      final current = line.codeUnitAt(i);
      final isHash = current == 0x23; // #
      final isSlash = current == 0x2F; // /
      if (!isHash && !isSlash) continue;

      if (!_isSpaceCodeUnit(line.codeUnitAt(i - 1))) continue;
      if (isSlash && (i + 1 >= line.length || line.codeUnitAt(i + 1) != 0x2F)) {
        continue;
      }
      return line.substring(0, i).trimRight();
    }
    return line;
  }

  static bool _isSpaceCodeUnit(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x3000;
}

/// One file (or other source) that contributed entries.
class WordListFile {
  const WordListFile({
    required this.source,
    required this.lines,
    required this.entries,
    required this.duplicates,
  });

  /// File name or path, as passed to the loader.
  final String source;

  /// How many data lines the source had.
  final int lines;

  /// How many unique entries it added to the merged list.
  final int entries;

  /// How many of its lines were duplicates (of this or an earlier source).
  final int duplicates;

  @override
  String toString() => '$source: $entries entr${entries == 1 ? 'y' : 'ies'}';
}

/// A merged, de-duplicated set of entries read from one or more word lists.
///
/// ```dart
/// final import = await loadWordLists('dist');          // every dist/*.txt
/// SafeTextFilter.init(language: Language.chinese, additionalWords: import.words);
/// ```
///
/// On the web, read the text yourself and build the import without the file
/// system:
///
/// ```dart
/// final text = await rootBundle.loadString('assets/words.txt');
/// final import = WordListImport.merge({'assets/words.txt': text});
/// ```
class WordListImport {
  WordListImport({
    required List<String> words,
    List<WordListFile> files = const [],
    List<String> warnings = const [],
    this.duplicates = 0,
  })  : words = List.unmodifiable(words),
        files = List.unmodifiable(files),
        warnings = List.unmodifiable(warnings);

  /// Parses and merges [texts], keyed by the source name used in stats and
  /// warnings.
  ///
  /// Entries are de-duplicated across all sources, case-insensitively, keeping
  /// the spelling that appeared first.
  factory WordListImport.merge(
    Map<String, String> texts, {
    bool allowInlineComments = true,
    int maxEntryRunes = 64,
  }) {
    final words = <String>[];
    final files = <WordListFile>[];
    final warnings = <String>[];
    final seen = <String>{};
    var duplicates = 0;

    for (final MapEntry(key: source, value: text) in texts.entries) {
      final parsed = WordListParser.parse(
        text,
        source: source,
        allowInlineComments: allowInlineComments,
        maxEntryRunes: maxEntryRunes,
      );

      warnings.addAll(parsed.warnings);
      final before = words.length;
      for (final word in parsed.words) {
        if (seen.add(word.toLowerCase())) words.add(word);
      }
      final added = words.length - before;

      files.add(WordListFile(
        source: source,
        lines: parsed.lines,
        entries: added,
        duplicates: parsed.lines - added,
      ));

      duplicates += parsed.lines - added;

      if (parsed.lines == 0) {
        warnings.add('$source: no entries found (the file is empty or only '
            'holds comments)');
      } else if (added == 0) {
        warnings.add('$source: every entry was already listed by an earlier '
            'file');
      }
    }

    return WordListImport(
      words: words,
      files: files,
      warnings: warnings,
      duplicates: duplicates,
    );
  }

  /// The merged entries, in the order they were first seen.
  final List<String> words;

  /// Per-source statistics, in the order the sources were read.
  final List<WordListFile> files;

  /// Problems worth reporting. Warnings never quote an entry.
  final List<String> warnings;

  /// How many data lines were dropped as duplicates.
  final int duplicates;

  /// The number of unique entries.
  int get count => words.length;

  /// Whether nothing was read.
  bool get isEmpty => words.isEmpty;

  @override
  String toString() {
    final parts = <String>[
      '${files.length} file${files.length == 1 ? '' : 's'}',
      '$count word${count == 1 ? '' : 's'}',
      if (duplicates > 0) '$duplicates duplicate${duplicates == 1 ? '' : 's'}',
      if (warnings.isNotEmpty)
        '${warnings.length} warning${warnings.length == 1 ? '' : 's'}',
    ];
    return 'WordListImport(${parts.join(', ')})';
  }
}
