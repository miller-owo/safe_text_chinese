# dist

Drop plain-text word lists here, one entry per line. **Every `*.txt` in this
folder is read** — `AAA.txt`, `BBB.txt`, `CCC.txt`, … — and everything they
contain is blocked. No categories, no metadata, no per-file configuration.

```text
# dist/AAA.txt
# Lines starting with # or // are comments.
AAA
BBB
CCC  # an inline comment after whitespace is dropped too
```

Load the whole folder once at startup:

```dart
import 'package:safe_text/safe_text.dart';

// This folder + the bundled English list — the default.
final import = await initFromWordLists('dist');

// Another bundled list instead of English:
final import = await initFromWordLists('dist', language: Language.chinese);

// This folder alone:
final import = await initFromWordLists('dist', includeBundledWords: false);

if (import.isEmpty) {
  // Nothing was read — do not ship an app with an empty filter.
  print(import.warnings);
}
```

Check the folder from the command line (prints counts only, never an entry):

```bash
dart run tool/check_word_lists.dart dist
```

Rules: UTF-8 (a BOM is fine), one entry per line, blank lines ignored,
duplicates dropped. See "Importing word lists" in the top-level README.

> **Platform note:** this folder is read through `dart:io`, so it works on CLI,
> desktop and test targets. A Flutter app does not ship repository folders — on
> mobile and web, register the lists as assets and read them with `rootBundle`,
> then `WordListImport.merge`.
