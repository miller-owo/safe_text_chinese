import 'models/language.dart';
import 'word_list_import.dart';

/// Reads plain-text word lists from disk and merges them into a
/// [WordListImport].
///
/// This is the platform stub. The real implementation lives in
/// `word_list_loader_io.dart` and is only compiled where `dart:io` exists; on
/// the web there is no file system, so this version throws.
///
/// On the web, load the text yourself and pass it to [WordListImport.merge]:
///
/// ```dart
/// final text = await rootBundle.loadString('assets/words.txt');
/// final import = WordListImport.merge({'assets/words.txt': text});
/// ```
Future<WordListImport> loadWordLists(
  Object source, {
  String extension = '.txt',
  bool recursive = false,
  bool allowInlineComments = true,
  int maxEntryRunes = 64,
}) async {
  throw UnsupportedError(
    'loadWordLists() needs dart:io, which is not available on the web. '
    'Load the word list text yourself (for example with rootBundle) and pass '
    'it to WordListImport.merge or WordListParser.parse.',
  );
}

/// Reads every word list under [source] and initializes the filter with them.
///
/// The platform stub for `initFromWordLists`; it throws on the web, where
/// there is no file system. Load the text with `rootBundle` and call
/// `WordListImport.merge` instead.
Future<WordListImport> initFromWordLists(
  Object source, {
  Language? language,
  List<Language>? languages,
  bool includeBundledWords = true,
  String extension = '.txt',
  bool recursive = false,
  bool allowInlineComments = true,
}) async {
  throw UnsupportedError(
    'initFromWordLists() needs dart:io, which is not available on the web. '
    'Load the word list text yourself (for example with rootBundle), build a '
    'WordListImport with WordListImport.merge, and pass its words to '
    'SafeTextFilter.init(additionalWords: ...).',
  );
}
