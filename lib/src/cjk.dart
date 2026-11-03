/// Helpers that make the matcher behave sensibly on CJK text.
///
/// Chinese, Japanese and Korean are written without spaces between words. The
/// word-boundary rule inherited from Latin word lists assumes that a letter
/// touching a match means the match is only part of a longer word — that is how
/// `ass` is kept out of `class`. Applied to CJK that rule rejects almost every
/// real occurrence, because a phrase in the middle of a Chinese sentence is
/// always surrounded by Han characters, and Han characters are letters.
///
/// The helpers below let the filter treat the spaceless scripts as "not a word
/// character", and let a phrase be matched across the separators people insert
/// to dodge Chinese filters (`坏 词`, `坏*词`, `坏​词`).
library;

/// Han ideographs: the common block, extension A, compatibility ideographs and
/// the supplementary-plane extensions (B and later).
bool isHanRune(int rune) =>
    (rune >= 0x3400 && rune <= 0x4DBF) || // CJK Extension A
    (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK Unified Ideographs
    (rune >= 0xF900 && rune <= 0xFAFF) || // CJK Compatibility Ideographs
    (rune >= 0x20000 && rune <= 0x2FA1F); // Extensions B–F and supplement

/// Scripts written without spaces between words: Han, kana and Hangul.
///
/// A character from one of these scripts does not mark the end of a word, so
/// it must not block a match the way a Latin letter does.
bool isSpacelessRune(int rune) =>
    isHanRune(rune) ||
    (rune >= 0x1100 && rune <= 0x11FF) || // Hangul Jamo
    (rune >= 0x3040 && rune <= 0x30FF) || // Hiragana + Katakana
    (rune >= 0x3130 && rune <= 0x318F) || // Hangul compatibility Jamo
    (rune >= 0x31F0 && rune <= 0x31FF) || // Katakana phonetic extensions
    (rune >= 0xA960 && rune <= 0xA97F) || // Hangul Jamo Extended-A
    (rune >= 0xAC00 && rune <= 0xD7FF); // Hangul syllables + Extended-B

final RegExp _wordRunePattern = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Whether [rune] is a letter or a digit in any script.
bool isWordRune(int rune) {
  // ASCII fast path; this is the hot loop for Latin text.
  if (rune < 0x80) {
    return (rune >= 0x30 && rune <= 0x39) || // 0-9
        (rune >= 0x41 && rune <= 0x5A) || // A-Z
        (rune >= 0x61 && rune <= 0x7A); // a-z
  }
  return _wordRunePattern.hasMatch(String.fromCharCode(rune));
}

/// Characters that end a clause or a line.
///
/// A phrase is never matched across one of these, so `坏。词` or a phrase split
/// over two lines stays untouched instead of being stitched back together.
const Set<int> _clauseBoundaryRunes = {
  0x0A, 0x0B, 0x0C, 0x0D, // line breaks
  0x2028, 0x2029, // line separator, paragraph separator
  0x21, 0x2C, 0x2E, 0x3A, 0x3B, 0x3F, // ! , . : ; ?
  0x2014, 0x2026, // — …
  0x3001, 0x3002, // 、 。
  0xFF01, 0xFF0C, 0xFF0E, 0xFF1A, 0xFF1B, 0xFF1F, // ！ ， ． ： ； ？
};

/// Whether [rune] may be dropped when looking for an obfuscated phrase.
///
/// These are the characters a filter has to skip over to catch `坏 词` or
/// `坏*词`: whitespace, zero-width characters, emoji and decoration. Letters
/// and digits never qualify, and neither does anything that ends a clause.
bool isGapRune(int rune) {
  if (_clauseBoundaryRunes.contains(rune)) return false;
  return !isWordRune(rune);
}

/// A rune list with its gap characters removed, still pointing back at the
/// source text.
class CompactedRunes {
  CompactedRunes._(this.runes, this.origin, this.sourceLength);

  /// The surviving runes, in order.
  final List<int> runes;

  /// For each rune in [runes], the index of that same rune in the source.
  final List<int> origin;

  /// The number of runes in the source text.
  final int sourceLength;

  /// Whether at least one gap character was removed.
  bool get hasGaps => runes.length < sourceLength;

  /// The index just past the source rune at [index] of [runes].
  int sourceEnd(int index) => origin[index] + 1;
}

/// Removes the gap characters (see [isGapRune]) from [runes].
CompactedRunes compactRunes(List<int> runes) {
  final compacted = <int>[];
  final origin = <int>[];
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    if (isGapRune(rune)) continue;
    compacted.add(rune);
    origin.add(i);
  }
  return CompactedRunes._(compacted, origin, runes.length);
}

/// Returns [text] with its gap characters removed, or `null` when there was
/// nothing to remove.
String? foldGaps(String text) {
  var changed = false;
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (isGapRune(rune)) {
      changed = true;
      continue;
    }
    buffer.writeCharCode(rune);
  }
  return changed ? buffer.toString() : null;
}
