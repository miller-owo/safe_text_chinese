import 'package:safe_text/constants/badwords.dart';

import 'aho_corasick.dart';
import 'cjk.dart';
import 'models/language.dart';
import 'models/mask_strategy.dart';

/// Core filter class that uses Aho-Corasick trie for efficient searching
///
/// ## Chinese and other CJK text
///
/// CJK scripts are written without spaces, so the Latin word-boundary rule
/// ("a letter next to the match means it is part of a longer word") would
/// reject almost every real Chinese sentence. Han, kana and Hangul characters
/// therefore never block a match, which is what lets a bundled phrase be found
/// in the middle of an ordinary sentence. Entries that are a single character
/// still need a real boundary on both sides, otherwise every occurrence of that
/// character would be flagged.
///
/// Chinese writers also break words up to dodge filters — `坏 词`, `坏*词`,
/// `坏​词` (with a zero-width space). Phrases of two or more characters are
/// matched across such separators too; see [tolerateCjkSeparators].
class SafeTextFilter {
  /// Entries without leet-speak characters, searched against normalized text
  /// so that obfuscated variants (e.g. `f@ck`, `fvck`) are caught.
  static AhoCorasick? _trie;

  /// Entries that contain leet-speak characters (e.g. `vagina`, `2g1c`),
  /// searched against lowercased text so they only match as written.
  /// Normalizing these instead would turn entries like the Arabizi `3ars`
  /// into ordinary words (`ears`).
  static AhoCorasick? _literalTrie;

  static bool _isInitialized = false;

  /// Whether a CJK phrase is also matched when the writer separated its
  /// characters with spaces, symbols, emoji or zero-width characters
  /// (`坏 词`, `坏*词`), which is one of the most common ways to dodge Chinese
  /// filters. Enabled by default.
  ///
  /// Only phrases of two or more characters take part in this, and a match is
  /// never stitched together across a clause boundary (punctuation, a line
  /// break). Set to `false` to require an exact, contiguous match.
  static bool tolerateCjkSeparators = true;

  /// Whether [SafeTextFilter] has been initialized via [init].
  static bool get isInitialized => _isInitialized;

  /// Resets the internal state of [SafeTextFilter], clearing the loaded Trie
  /// word lists. Useful when dynamically switching languages or freeing memory.
  static void reset() {
    _trie = null;
    _literalTrie = null;
    _isInitialized = false;
  }

  // Normalization map to catch leet-speak and common variations
  static final Map<int, int> _normalizationMap = {
    '@'.codeUnitAt(0): 'a'.codeUnitAt(0),
    '4'.codeUnitAt(0): 'a'.codeUnitAt(0),
    '8'.codeUnitAt(0): 'b'.codeUnitAt(0),
    '('.codeUnitAt(0): 'c'.codeUnitAt(0),
    '3'.codeUnitAt(0): 'e'.codeUnitAt(0),
    '1'.codeUnitAt(0): 'i'.codeUnitAt(0),
    '!'.codeUnitAt(0): 'i'.codeUnitAt(0),
    '0'.codeUnitAt(0): 'o'.codeUnitAt(0),
    '\$'.codeUnitAt(0): 's'.codeUnitAt(0),
    '5'.codeUnitAt(0): 's'.codeUnitAt(0),
    '7'.codeUnitAt(0): 't'.codeUnitAt(0),
    '+'.codeUnitAt(0): 't'.codeUnitAt(0),
    'v'.codeUnitAt(0): 'u'.codeUnitAt(0),
    '#'.codeUnitAt(0): 'h'.codeUnitAt(0),
  };

  /// Initializes the SafeTextFilter.
  /// You can provide a single [language] or a list of [languages].
  /// If [languages] is provided, it takes precedence over [language].
  /// Defaults to [Language.english] if both are null.
  ///
  /// [additionalWords] join the bundled list in the same trie, so they get the
  /// same matching rules (leet-speak, CJK boundaries, separator tolerance).
  /// That is how a project's own list is loaded, for example
  /// `additionalWords: (await loadWordLists('dist')).words`.
  ///
  /// Pass `includeBundledWords: false` to build the filter from
  /// [additionalWords] alone.
  static void init({
    Language? language,
    List<Language>? languages,
    Iterable<String>? additionalWords,
    bool includeBundledWords = true,
  }) {
    final words = _loadWords(
      language: language,
      languages: languages,
      additionalWords: additionalWords,
      includeBundledWords: includeBundledWords,
    );

    // Building the Trie locally is fast and avoids serialization overhead
    final trie = AhoCorasick();
    final literalTrie = AhoCorasick();
    for (var word in words) {
      _insertWord(trie, literalTrie, word);
      _insertCompactedWord(trie, literalTrie, word);
    }
    _trie = trie..buildFailureLinks();
    _literalTrie = literalTrie..buildFailureLinks();

    _isInitialized = true;
  }

  /// Inserts [word] into the trie that can match it: entries containing a
  /// character that normalization rewrites (`v`, digits, symbols, full-width
  /// forms) are matched literally, every other entry against normalized text.
  static void _insertWord(
      AhoCorasick trie, AhoCorasick literalTrie, String word) {
    final lower = word.toLowerCase();
    (_hasMappedChar(lower.runes) ? literalTrie : trie).addWord(lower);
  }

  /// Also registers the spelling of [word] with its gap characters removed.
  ///
  /// Bundled lists sometimes store a phrase with a space between its characters
  /// (a spaced-out spelling of the same phrase); without this, such an entry
  /// would never match the phrase as it is normally written.
  static void _insertCompactedWord(
      AhoCorasick trie, AhoCorasick literalTrie, String word) {
    if (!tolerateCjkSeparators) return;
    if (!word.runes.any(isHanRune)) return;

    final compacted = foldGaps(word.toLowerCase());
    if (compacted == null || !_supportsGapMatching(compacted)) return;
    _insertWord(trie, literalTrie, compacted);
  }

  static void _ensureInitialized() {
    if (_trie == null) init();
  }

  static List<String> _loadWords({
    Language? language,
    List<Language>? languages,
    Iterable<String>? additionalWords,
    bool includeBundledWords = true,
  }) {
    final List<String> words = [];

    if (includeBundledWords) {
      if (languages != null && languages.isNotEmpty) {
        for (var l in languages) {
          words.addAll(l.words);
        }
      } else {
        final lang = language ?? Language.english;
        words.addAll(lang.words);
      }

      if (words.isEmpty) {
        words.addAll(badWords);
      }
    }

    if (additionalWords != null) {
      words.addAll(additionalWords);
    }
    return words.toSet().toList();
  }

  /// Normalizes text by replacing leet-speak with standard alphabets.
  ///
  /// Full-width forms (`ｆ`, `４`, `＠`) are folded onto their ASCII
  /// counterparts first, so text typed with a Chinese IME is normalized the
  /// same way as text typed with a Latin keyboard.
  static String normalizeText(String text) {
    if (text.isEmpty) return text;
    final runes = _normalizeToRunes(text);
    return String.fromCharCodes(runes);
  }

  static List<int> _normalizeToRunes(String text) =>
      _normalizeRunes(text.toLowerCase().runes.toList());

  /// Returns a copy of [lowerRunes] with leet-speak characters replaced.
  static List<int> _normalizeRunes(List<int> lowerRunes) {
    final runes = List<int>.of(lowerRunes);
    for (int i = 0; i < runes.length; i++) {
      final folded = _foldFullWidth(runes[i]);
      runes[i] = _normalizationMap[folded] ?? folded;
    }
    return runes;
  }

  /// Maps a full-width ASCII character (U+FF01–U+FF5E) onto its ASCII
  /// counterpart; any other rune is returned unchanged.
  static int _foldFullWidth(int rune) =>
      (rune >= 0xFF01 && rune <= 0xFF5E) ? rune - 0xFEE0 : rune;

  /// Whether any rune in [runes] is rewritten by [_normalizeRunes].
  ///
  /// Text containing such a rune can still match entries that are stored
  /// literally, so the literal trie is searched over it as well.
  static bool _hasMappedChar(Iterable<int> runes) => runes.any((rune) =>
      _normalizationMap.containsKey(rune) || _foldFullWidth(rune) != rune);

  /// Static method to check if a string contains any bad words.
  static bool containsBadWord({
    required String text,
    List<String>? extraWords,
    List<String>? excludedWords,
    bool useDefaultWords = true,
  }) {
    if (text.isEmpty) return false;

    return _collectMatches(
      text,
      extraWords: extraWords,
      excludedWords: excludedWords,
      useDefaultWords: useDefaultWords,
    ).isNotEmpty;
  }

  /// Finds the rune ranges of every bad word in [text].
  ///
  /// Words without leet-speak characters are matched against the normalized
  /// text; words containing them are matched literally against the lowercased
  /// text (see [_literalTrie]). Text that contains Han characters is also
  /// searched with its gap characters removed, so that a phrase broken up with
  /// spaces or symbols is still caught.
  static List<_Range> _collectMatches(
    String text, {
    List<String>? extraWords,
    List<String>? excludedWords,
    required bool useDefaultWords,
  }) {
    final lowerRunes = text.toLowerCase().runes.toList();
    final normalizedRunes = _normalizeRunes(lowerRunes);
    final hasMapped = _hasMappedChar(lowerRunes);
    final matchRanges = <_Range>[];

    // Separator-tolerant matching only makes sense for CJK text; skipping it
    // for everything else keeps the Latin path as fast as it was.
    final gapMatching = tolerateCjkSeparators && lowerRunes.any(isHanRune);
    final compactedNormalized =
        gapMatching ? compactRunes(normalizedRunes) : null;
    final compactedLiteral =
        gapMatching && hasMapped ? compactRunes(lowerRunes) : null;

    final excludedNormalized = <String>{};
    final excludedLiteral = <String>{};
    for (final word in excludedWords ?? const <String>[]) {
      excludedLiteral.add(word.toLowerCase());

      final normalized = normalizeText(word);
      excludedNormalized.add(normalized);

      // A phrase excluded in one spelling must stay excluded in the other.
      final compacted = tolerateCjkSeparators ? foldGaps(normalized) : null;
      if (compacted != null) excludedNormalized.add(compacted);
    }

    if (useDefaultWords) {
      _ensureInitialized();
      _addTrieMatches(_trie!, normalizedRunes, excludedNormalized, matchRanges);
      if (hasMapped) {
        _addTrieMatches(
            _literalTrie!, lowerRunes, excludedLiteral, matchRanges);
      }
      if (compactedNormalized != null && compactedNormalized.hasGaps) {
        _addGapTrieMatches(_trie!, normalizedRunes, compactedNormalized,
            excludedNormalized, matchRanges);
      }
      if (compactedLiteral != null && compactedLiteral.hasGaps) {
        _addGapTrieMatches(_literalTrie!, lowerRunes, compactedLiteral,
            excludedLiteral, matchRanges);
      }
    }

    for (final word in extraWords ?? const <String>[]) {
      final lower = word.toLowerCase();
      if (!_hasMappedChar(lower.runes)) {
        if (excludedNormalized.contains(lower)) continue;
        _addMatchesForWord(normalizedRunes, lower, matchRanges);
        if (compactedNormalized != null && compactedNormalized.hasGaps) {
          _addGapMatchesForWord(
              normalizedRunes, compactedNormalized, lower, matchRanges);
        }
      } else if (hasMapped && !excludedLiteral.contains(lower)) {
        _addMatchesForWord(lowerRunes, lower, matchRanges);
        if (compactedLiteral != null && compactedLiteral.hasGaps) {
          _addGapMatchesForWord(
              lowerRunes, compactedLiteral, lower, matchRanges);
        }
      }
    }

    return matchRanges;
  }

  static void _addTrieMatches(AhoCorasick trie, List<int> runes,
      Set<String> excluded, List<_Range> matches) {
    trie.searchRunes(runes).forEach((endIndex, words) {
      for (final word in words) {
        if (excluded.contains(word)) continue;
        final startIndex = endIndex - word.runes.length + 1;
        if (_isWordBoundary(runes, startIndex, endIndex + 1,
            requireSpacelessBoundary: word.runes.length == 1)) {
          matches.add(_Range(startIndex, endIndex + 1));
        }
      }
    });
  }

  /// Adds matches for phrases whose characters are separated by gap
  /// characters in the source text (`坏 词`, `坏*词`, `坏​词`).
  static void _addGapTrieMatches(
    AhoCorasick trie,
    List<int> sourceRunes,
    CompactedRunes compacted,
    Set<String> excluded,
    List<_Range> matches,
  ) {
    trie.searchRunes(compacted.runes).forEach((endIndex, words) {
      for (final word in words) {
        if (excluded.contains(word)) continue;
        if (!_supportsGapMatching(word)) continue;
        final startIndex = endIndex - word.runes.length + 1;
        if (startIndex < 0) continue;
        _addGapRange(sourceRunes, compacted, startIndex, endIndex,
            word.runes.length, matches);
      }
    });
  }

  /// Maps a match found in [compacted] back onto [sourceRunes] and records it.
  static void _addGapRange(
    List<int> sourceRunes,
    CompactedRunes compacted,
    int startIndex,
    int endIndex,
    int wordLength,
    List<_Range> matches,
  ) {
    final start = compacted.origin[startIndex];
    final end = compacted.sourceEnd(endIndex);

    // Bail out when the filler is longer than the phrase itself: that is two
    // unrelated words sitting next to each other, not an obfuscated one.
    if (end - start - wordLength > wordLength + 2) return;

    if (!_isWordBoundary(sourceRunes, start, end)) return;
    matches.add(_Range(start, end));
  }

  /// Whether [word] may also be matched when its characters are separated by
  /// gap characters.
  ///
  /// Restricted to entries containing a Han character and at least two runes: a
  /// single character is too common to match loosely, and purely Latin entries
  /// are already covered by leet-speak normalization.
  static bool _supportsGapMatching(String word) {
    final runes = word.runes.toList();
    return runes.length >= 2 && runes.any(isHanRune);
  }

  /// This method will filter out the bad words from your provided [string].
  static String filterText({
    required String text,
    List<String>? extraWords,
    List<String>? excludedWords,
    bool useDefaultWords = true,
    @Deprecated('Use strategy instead.') bool fullMode = true,
    @Deprecated(
      'Use strategy instead. Pass obscureSymbol via MaskStrategy.full() or MaskStrategy.partial().',
    )
    String obscureSymbol = "*",
    MaskStrategy? strategy,
  }) {
    if (useDefaultWords == false && extraWords == null) {
      assert(false, "extraWords can't be null for usingDefaultWords = false");
    }

    assert(() {
      final excluded = {for (final w in excludedWords ?? []) w.toLowerCase()};
      return !(extraWords ?? []).any((w) => excluded.contains(w.toLowerCase()));
    }(), "Can't have same words in excludedWords and extraWords");

    // Derive the effective masking strategy. When the caller passes an explicit
    // [strategy] it takes precedence. Otherwise fall back to the legacy
    // [fullMode] / [obscureSymbol] pair so that existing call sites continue to
    // work without modification.
    final MaskStrategy maskStrategy = strategy ??
        (fullMode
            ? MaskStrategy.full(obscureSymbol: obscureSymbol)
            : MaskStrategy.partial(obscureSymbol: obscureSymbol));

    if (text.isEmpty) return text;

    final textRunes = text.runes.toList();

    // Step 1: Collect match ranges
    final matchRanges = _collectMatches(
      text,
      extraWords: extraWords,
      excludedWords: excludedWords,
      useDefaultWords: useDefaultWords,
    );

    if (matchRanges.isEmpty) return text;

    // Step 2: Sort and merge ranges
    matchRanges.sort((a, b) => a.start.compareTo(b.start));
    final List<_Range> merged = [];
    if (matchRanges.isNotEmpty) {
      _Range current = matchRanges[0];
      for (int i = 1; i < matchRanges.length; i++) {
        if (matchRanges[i].start < current.end) {
          if (matchRanges[i].end > current.end) {
            current = _Range(current.start, matchRanges[i].end);
          }
        } else {
          merged.add(current);
          current = matchRanges[i];
        }
      }
      merged.add(current);
    }

    // Step 3: Single-pass string building
    final buffer = StringBuffer();
    int lastAppended = 0;

    for (final range in merged) {
      buffer.write(
          String.fromCharCodes(textRunes.sublist(lastAppended, range.start)));

      final matchLength = range.end - range.start;
      switch (maskStrategy) {
        // Full: replace every character with the obscure symbol
        case FullMask(:final obscureSymbol):
          buffer.write(obscureSymbol * matchLength);

        // Partial: keep first char visible, mask the rest.
        // For 4+ letter words, also keep the last char visible.
        case PartialMask(:final obscureSymbol):
          if (matchLength == 1) {
            buffer.write(obscureSymbol);
          } else {
            final showLast = matchLength >= 4;
            final maskCount = matchLength - 1 - (showLast ? 1 : 0);
            buffer
              ..write(String.fromCharCode(textRunes[range.start]))
              ..write(obscureSymbol * maskCount);
            if (showLast) {
              buffer.write(String.fromCharCode(textRunes[range.end - 1]));
            }
          }

        // Custom: replace entire word with the replacement string
        case CustomMask(:final replacement):
          buffer.write(replacement);
      }
      lastAppended = range.end;
    }

    if (lastAppended < textRunes.length) {
      buffer.write(String.fromCharCodes(textRunes.sublist(lastAppended)));
    }

    return buffer.toString();
  }

  static void _addMatchesForWord(
      List<int> runes, String lowerWord, List<_Range> matches) {
    final wordRunes = lowerWord.runes.toList();
    if (wordRunes.isEmpty) return;

    for (int i = 0; i <= runes.length - wordRunes.length; i++) {
      bool match = true;
      for (int j = 0; j < wordRunes.length; j++) {
        if (runes[i + j] != wordRunes[j]) {
          match = false;
          break;
        }
      }

      if (match) {
        final endIndex = i + wordRunes.length;
        if (_isWordBoundary(runes, i, endIndex,
            requireSpacelessBoundary: wordRunes.length == 1)) {
          matches.add(_Range(i, endIndex));
        }
      }
    }
  }

  /// Same as [_addMatchesForWord], but for an extra word whose characters the
  /// writer may have separated with gap characters.
  static void _addGapMatchesForWord(
    List<int> sourceRunes,
    CompactedRunes compacted,
    String lowerWord,
    List<_Range> matches,
  ) {
    if (!_supportsGapMatching(lowerWord)) return;

    final wordRunes = lowerWord.runes.toList();
    for (int i = 0; i <= compacted.runes.length - wordRunes.length; i++) {
      bool match = true;
      for (int j = 0; j < wordRunes.length; j++) {
        if (compacted.runes[i + j] != wordRunes[j]) {
          match = false;
          break;
        }
      }

      if (match) {
        _addGapRange(sourceRunes, compacted, i, i + wordRunes.length - 1,
            wordRunes.length, matches);
      }
    }
  }

  /// Whether the match spanning `[start, end)` in [runes] is delimited.
  ///
  /// Letters and digits normally block a match, which is what keeps `ass` out
  /// of `class`. Han, kana and Hangul do not: those scripts are written without
  /// spaces, so a phrase inside `这是坏词啊` is a complete phrase and must be
  /// caught. Pass [requireSpacelessBoundary] for single-character entries, where
  /// a looser rule would match almost everywhere.
  static bool _isWordBoundary(List<int> runes, int start, int end,
      {bool requireSpacelessBoundary = false}) {
    if (start > 0 &&
        _blocksBoundary(runes[start - 1], requireSpacelessBoundary)) {
      return false;
    }
    if (end < runes.length &&
        _blocksBoundary(runes[end], requireSpacelessBoundary)) {
      return false;
    }
    return true;
  }

  static bool _blocksBoundary(int rune, bool requireSpacelessBoundary) {
    if (isSpacelessRune(rune)) return requireSpacelessBoundary;
    return isWordRune(rune);
  }
}

class _Range {
  final int start;
  final int end;
  _Range(this.start, this.end);
}
