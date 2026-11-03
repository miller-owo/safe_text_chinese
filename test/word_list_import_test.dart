import 'dart:convert';
import 'dart:io';

import 'package:safe_text/safe_text.dart';
import 'package:test/test.dart';

void main() {
  group('WordListParser', () {
    test('reads one entry per line', () {
      final result = WordListParser.parse('AAA\nBBB\nCCC');

      expect(result.words, ['AAA', 'BBB', 'CCC']);
      expect(result.lines, 3);
      expect(result.duplicates, 0);
      expect(result.warnings, isEmpty);
    });

    test('handles CRLF, blank lines and a trailing newline', () {
      final result = WordListParser.parse('AAA\r\n\r\nBBB\r\n  \r\nCCC\r\n');

      expect(result.words, ['AAA', 'BBB', 'CCC']);
      expect(result.lines, 3);
    });

    test('strips a UTF-8 byte-order mark', () {
      expect(WordListParser.parse('\uFEFFAAA\nBBB').words, ['AAA', 'BBB']);
    });

    test('trims surrounding whitespace', () {
      expect(WordListParser.parse('  AAA  \n\tBBB\t').words, ['AAA', 'BBB']);
    });

    test('ignores comment lines', () {
      final result = WordListParser.parse('# header\nAAA\n// note\nBBB');

      expect(result.words, ['AAA', 'BBB']);
      expect(result.lines, 2);
    });

    test('drops an inline comment after whitespace', () {
      final result = WordListParser.parse('AAA # first\nBBB // second\nCCC');

      expect(result.words, ['AAA', 'BBB', 'CCC']);
    });

    test('keeps # and // inside an entry', () {
      expect(
        WordListParser.parse('c#\nhttp://example.com/x').words,
        ['c#', 'http://example.com/x'],
      );
    });

    test('can keep inline hashes when comments are disabled', () {
      final result =
          WordListParser.parse('AAA # keep', allowInlineComments: false);

      expect(result.words, ['AAA # keep']);
    });

    test('removes duplicates case-insensitively', () {
      final result = WordListParser.parse('AAA\nAAA\naaa\nBBB');

      expect(result.words, ['AAA', 'BBB']);
      expect(result.lines, 4);
      expect(result.duplicates, 2);
    });

    test('keeps Chinese entries as written', () {
      expect(
        WordListParser.parse('甲乙丙\n测试词甲\n').words,
        ['甲乙丙', '测试词甲'],
      );
    });

    test('warns about a very long entry without quoting it', () {
      final long = 'X' * 70;
      final result = WordListParser.parse('$long\nAAA');

      expect(result.words, [long, 'AAA']);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, contains(':1:'));
      expect(result.warnings.single, isNot(contains(long)));
    });

    test('returns nothing for an empty text', () {
      final result = WordListParser.parse('');

      expect(result.words, isEmpty);
      expect(result.lines, 0);
      expect(result.warnings, isEmpty);
    });
  });

  group('WordListImport.merge', () {
    test('merges sources and counts duplicates per file', () {
      final import = WordListImport.merge({
        'a.txt': 'AAA\nBBB',
        'b.txt': 'BBB\nCCC',
      });

      expect(import.words, ['AAA', 'BBB', 'CCC']);
      expect(import.count, 3);
      expect(import.files, hasLength(2));
      expect(import.files[0].entries, 2);
      expect(import.files[1].entries, 1);
      expect(import.files[1].duplicates, 1);
      expect(import.duplicates, 1);
      expect(import.isEmpty, isFalse);
    });

    test('warns about a source with no entries', () {
      final import = WordListImport.merge({'a.txt': '# only a comment'});

      expect(import.isEmpty, isTrue);
      expect(import.warnings.single, contains('a.txt'));
    });

    test('warns about a source that only repeats earlier entries', () {
      final import = WordListImport.merge({'a.txt': 'AAA', 'b.txt': 'AAA'});

      expect(import.warnings, hasLength(1));
      expect(import.warnings.single, contains('b.txt'));
    });

    test('summarises itself', () {
      final import = WordListImport.merge({'a.txt': 'AAA\nBBB'});

      expect(import.toString(), contains('1 file'));
      expect(import.toString(), contains('2 words'));
    });
  });

  group('loadWordLists', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('safe_text_words_'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    File write(String name, String content) =>
        File('${dir.path}${Platform.pathSeparator}$name')
          ..createSync(recursive: true)
          ..writeAsStringSync(content, encoding: utf8);

    test('loads every .txt in a directory in name order', () async {
      write('a.txt', 'AAA\nBBB\n');
      write('b.txt', 'CCC\n');

      final import = await loadWordLists(dir);

      expect(import.words, ['AAA', 'BBB', 'CCC']);
      expect(import.files, hasLength(2));
      expect(
          import.files.every((file) => file.source.endsWith('.txt')), isTrue);
    });

    test('accepts a path string', () async {
      write('a.txt', 'AAA\n');

      expect((await loadWordLists(dir.path)).words, ['AAA']);
    });

    test('accepts a glob pattern', () async {
      write('a.txt', 'AAA\n');
      write('b.txt', 'BBB\n');

      final import =
          await loadWordLists('${dir.path}${Platform.pathSeparator}*.txt');

      expect(import.words, ['AAA', 'BBB']);
    });

    test('accepts a single file and a list of sources', () async {
      final a = write('a.txt', 'AAA\n');
      final b = write('b.txt', 'BBB\n');

      expect((await loadWordLists(a)).words, ['AAA']);
      expect((await loadWordLists([a, b])).words, ['AAA', 'BBB']);
    });

    test('ignores other extensions and subdirectories', () async {
      write('a.txt', 'AAA\n');
      write('notes.md', 'BBB\n');
      write('sub${Platform.pathSeparator}c.txt', 'CCC\n');

      expect((await loadWordLists(dir)).words, ['AAA']);
    });

    test('recurses when asked', () async {
      write('a.txt', 'AAA\n');
      write('sub${Platform.pathSeparator}c.txt', 'CCC\n');

      expect((await loadWordLists(dir, recursive: true)).words, ['AAA', 'CCC']);
    });

    test('reads a byte-order mark and CRLF correctly', () async {
      File('${dir.path}${Platform.pathSeparator}bom.txt').writeAsBytesSync(
          [0xEF, 0xBB, 0xBF, ...utf8.encode('AAA\r\nBBB\r\n')]);

      expect((await loadWordLists(dir)).words, ['AAA', 'BBB']);
    });

    test('throws when the path does not exist', () {
      expect(
        loadWordLists('${dir.path}${Platform.pathSeparator}nope'),
        throwsA(isA<WordListFormatException>()),
      );
    });

    test('throws when a file is not UTF-8', () {
      File('${dir.path}${Platform.pathSeparator}bad.txt')
          .writeAsBytesSync([0xFF, 0xFE, 0x41]);

      expect(
        loadWordLists(dir),
        throwsA(isA<WordListFormatException>()),
      );
    });

    test('rejects a source that is not a path', () {
      expect(loadWordLists(42), throwsA(isA<ArgumentError>()));
    });

    test('warns when nothing matches', () async {
      final import = await loadWordLists(dir);

      expect(import.isEmpty, isTrue);
      expect(import.warnings, hasLength(1));
      expect(import.warnings.single, contains('.txt'));
    });
  });

  group('initFromWordLists', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('safe_text_dist_'));
    tearDown(() {
      SafeTextFilter.reset();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    File write(String name, String content) =>
        File('${dir.path}${Platform.pathSeparator}$name')
          ..createSync(recursive: true)
          ..writeAsStringSync(content, encoding: utf8);

    test('blocks every *.txt in a AAA.txt / BBB.txt / CCC.txt folder',
        () async {
      write('AAA.txt', '甲乙丙\n');
      write('BBB.txt', '测试词甲\n');
      write('CCC.txt', '丁戊\n');
      write('notes.md', '忽略\n');

      final import = await initFromWordLists(dir, includeBundledWords: false);

      expect(import.count, 3);
      expect(SafeTextFilter.filterText(text: '前面甲乙丙后面'), '前面***后面');
      expect(SafeTextFilter.filterText(text: '前面测试词甲后面'), '前面****后面');
      expect(SafeTextFilter.filterText(text: '前面丁戊后面'), '前面**后面');
      expect(SafeTextFilter.filterText(text: '普通的一句话'), '普通的一句话');
    });

    test('merges the folder with the bundled English list by default',
        () async {
      write('AAA.txt', '甲乙丙\n');
      final english = Language.english.words
          .firstWhere((word) => RegExp(r'^[A-Za-z]{4,}$').hasMatch(word))
          .toLowerCase();

      final import = await initFromWordLists(dir);

      expect(import.count, 1);
      expect(SafeTextFilter.filterText(text: '前面甲乙丙后面'), '前面***后面');
      expect(
        SafeTextFilter.filterText(text: 'please say $english now'),
        isNot(contains(english)),
      );
    });

    test('can merge the folder with a bundled language list', () async {
      write('AAA.txt', '甲乙丙\n');

      final import = await initFromWordLists(dir, language: Language.chinese);

      expect(import.count, 1);
      expect(SafeTextFilter.isInitialized, isTrue);
      expect(SafeTextFilter.filterText(text: '前面有甲乙丙，后面'), '前面有***，后面');
    });

    test('reports an empty folder instead of throwing', () async {
      final import = await initFromWordLists(dir, includeBundledWords: false);

      expect(import.isEmpty, isTrue);
      expect(import.warnings, isNotEmpty);
      expect(SafeTextFilter.filterText(text: '甲乙丙'), '甲乙丙');
    });
  });

  group('filter integration', () {
    tearDown(SafeTextFilter.reset);

    test('imported words are masked inside Chinese sentences', () {
      SafeTextFilter.init(
        includeBundledWords: false,
        additionalWords: const ['甲乙丙'],
      );

      expect(SafeTextFilter.filterText(text: '这是甲乙丙啊'), '这是***啊');
    });

    test('imported words are masked when spaced out', () {
      SafeTextFilter.init(
        includeBundledWords: false,
        additionalWords: const ['甲乙丙'],
      );

      expect(SafeTextFilter.filterText(text: '甲 乙 丙'), '*****');
    });

    test('includeBundledWords: false leaves the bundled list out', () {
      SafeTextFilter.init(
        includeBundledWords: false,
        additionalWords: const ['甲乙丙'],
      );

      expect(SafeTextFilter.containsBadWord(text: 'zzz and 甲乙丙'), isTrue);
      expect(SafeTextFilter.filterText(text: 'zzz'), 'zzz');
    });

    test('bundled words stay in when the import is added', () {
      SafeTextFilter.init(
        language: Language.chinese,
        additionalWords: const ['甲乙丙'],
      );

      expect(SafeTextFilter.filterText(text: '这句甲乙丙'), '这句***');
    });

    test('excludedWords still wins over an imported word', () {
      SafeTextFilter.init(
        includeBundledWords: false,
        additionalWords: const ['甲乙丙'],
      );

      expect(
        SafeTextFilter.filterText(
          text: '甲乙丙',
          excludedWords: const ['甲乙丙'],
        ),
        '甲乙丙',
      );
    });

    test('loads a directory into the filter end to end', () async {
      final directory = Directory.systemTemp.createTempSync('safe_text_e2e_');
      addTearDown(() => directory.deleteSync(recursive: true));
      File('${directory.path}${Platform.pathSeparator}words.txt')
          .writeAsStringSync('甲乙丙\n测试词甲\n', encoding: utf8);

      final import = await loadWordLists(directory);
      SafeTextFilter.init(
        language: Language.chinese,
        additionalWords: import.words,
      );

      expect(SafeTextFilter.filterText(text: '前面有甲乙丙，后面'), '前面有***，后面');
      expect(
        SafeTextFilter.filterText(text: '前面有测 试 词 甲，后面'),
        '前面有*******，后面',
      );
    });
  });
}
