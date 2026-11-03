import 'package:safe_text/safe_text.dart';
import 'package:safe_text/src/cjk.dart';
import 'package:test/test.dart';

/// These tests use made-up markers instead of real entries: they exercise the
/// matcher, not the bundled word lists. The one test that does use a bundled
/// Chinese entry picks it at runtime, so no offensive text lives in this file.
const marker = '甲乙丙';

String filter(
  String text, {
  List<String>? extraWords,
  List<String>? excludedWords,
}) =>
    SafeTextFilter.filterText(
      text: text,
      extraWords: extraWords ?? const [marker],
      excludedWords: excludedWords,
      useDefaultWords: false,
      strategy: const MaskStrategy.full(),
    );

void main() {
  group('Han phrases inside running text', () {
    test('matches when surrounded by other Han characters', () {
      expect(filter('这是甲乙丙啊'), '这是***啊');
    });

    test('matches next to Han punctuation', () {
      expect(filter('甲乙丙。'), '***。');
    });

    test('does not need spaces to match', () {
      expect(filter('前面甲乙丙后面'), '前面***后面');
    });
  });

  group('separator-tolerant matching', () {
    test('matches across spaces', () {
      expect(filter('甲乙 丙'), '****');
    });

    test('matches across asterisks and decorations', () {
      expect(filter('甲*乙*丙'), '*****');
      expect(filter('甲～乙～丙'), '*****');
    });

    test('matches across zero-width characters', () {
      expect(filter('甲\u200b乙\u200c丙'), '*****');
    });

    test('matches across an emoji', () {
      expect(filter('甲😀乙😀丙'), '*****');
    });

    test('never bridges a clause boundary', () {
      expect(filter('甲乙。丙'), '甲乙。丙');
      expect(filter('甲乙，丙'), '甲乙，丙');
    });

    test('never bridges a line break', () {
      expect(filter('甲乙\n丙'), '甲乙\n丙');
    });

    test('gives up when the filler is longer than the phrase', () {
      expect(filter('甲       乙丙'), '甲       乙丙');
    });

    test('can be switched off', () {
      SafeTextFilter.tolerateCjkSeparators = false;
      addTearDown(() => SafeTextFilter.tolerateCjkSeparators = true);

      expect(filter('甲乙 丙'), '甲乙 丙');
      expect(filter('甲乙丙'), '***');
    });
  });

  group('single Han characters', () {
    test('need a real boundary on both sides', () {
      expect(filter('甲鱼', extraWords: const ['甲']), '甲鱼');
      expect(filter('甲，鱼', extraWords: const ['甲']), '*，鱼');
      expect(filter(' 甲 ', extraWords: const ['甲']), ' * ');
    });
  });

  group('Latin words next to Han text', () {
    test('are matched without spaces', () {
      expect(filter('说zzq啊', extraWords: const ['zzq']), '说***啊');
    });

    test('are still rejected inside a longer Latin word', () {
      expect(filter('azzqb', extraWords: const ['zzq']), 'azzqb');
    });

    test('full-width spellings are folded', () {
      expect(filter('ｚｚｑ', extraWords: const ['zzq']), '***');
    });
  });

  group('bundled Chinese list', () {
    setUpAll(() => SafeTextFilter.init(language: Language.chinese));
    tearDownAll(SafeTextFilter.reset);

    test('finds an entry in the middle of a sentence', () {
      final entry = Language.chinese.words.firstWhere(
        (word) => word.runes.length == 2 && word.runes.every(isHanRune),
      );
      final text = '随便说一句，其中有$entry这两个字，后面继续。';
      final filtered = SafeTextFilter.filterText(text: text);

      expect(filtered, isNot(equals(text)));
      expect(filtered.contains(entry), isFalse);
      // Full masking keeps the rune count, so nothing was swallowed.
      expect(filtered.runes.length, text.runes.length);
      expect(SafeTextFilter.containsBadWord(text: text), isTrue);
    });

    test('finds an entry the writer spaced out', () {
      final entry = Language.chinese.words.firstWhere(
        (word) => word.runes.length == 2 && word.runes.every(isHanRune),
      );
      final spaced = entry.runes.map(String.fromCharCode).join(' ');
      final text = '随便说一句，其中有$spaced这两个字，后面继续。';
      final filtered = SafeTextFilter.filterText(text: text);

      expect(filtered.contains(spaced), isFalse);
      expect(filtered.runes.length, text.runes.length);
    });

    test('leaves ordinary text untouched', () {
      const clean = '今天天气不错，我们去公园散步。';
      expect(SafeTextFilter.filterText(text: clean), clean);
    });
  });
}
