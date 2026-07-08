import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BabehReaderApp());
}

class BabehReaderApp extends StatelessWidget {
  const BabehReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Babeh Reader',
      theme: AppThemes.light,
      darkTheme: AppThemes.dark,
      themeMode: ThemeMode.system,
      home: const OfflineReaderHome(),
    );
  }
}

class AppThemes {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C63FF),
      brightness: Brightness.light,
      surface: const Color(0xFFF8F7FC),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF8F7FC),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
      ),
    );
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF9B8CFF),
      brightness: Brightness.dark,
      surface: const Color(0xFF111118),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF111118),
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}

enum BookFormat { pdf, epub, txt, cbz, unknown }

enum HomeSection { dashboard, library, continueReading, favorites, bookmarks, collections, statistics, settings, about }

extension BookFormatX on BookFormat {
  String get label {
    switch (this) {
      case BookFormat.pdf:
        return 'PDF';
      case BookFormat.epub:
        return 'EPUB';
      case BookFormat.txt:
        return 'TXT';
      case BookFormat.cbz:
        return 'CBZ';
      case BookFormat.unknown:
        return 'File';
    }
  }

  IconData get icon {
    switch (this) {
      case BookFormat.pdf:
        return CupertinoIcons.doc_richtext;
      case BookFormat.epub:
        return CupertinoIcons.book;
      case BookFormat.txt:
        return CupertinoIcons.text_alignleft;
      case BookFormat.cbz:
        return CupertinoIcons.photo_on_rectangle;
      case BookFormat.unknown:
        return CupertinoIcons.doc;
    }
  }
}

class BookItem {
  const BookItem({
    required this.id,
    required this.title,
    required this.author,
    required this.path,
    required this.format,
    required this.addedAt,
    required this.lastOpenedAt,
    required this.progress,
    required this.favorite,
    required this.totalUnits,
    required this.accent,
  });

  final String id;
  final String title;
  final String author;
  final String path;
  final BookFormat format;
  final DateTime addedAt;
  final DateTime? lastOpenedAt;
  final double progress;
  final bool favorite;
  final int totalUnits;
  final int accent;

  bool get exists => File(path).existsSync();
  bool get isStarted => progress > 0.001;
  bool get isFinished => progress >= 0.985;

  BookItem copyWith({
    String? title,
    String? author,
    String? path,
    BookFormat? format,
    DateTime? addedAt,
    Object? lastOpenedAt = _sentinel,
    double? progress,
    bool? favorite,
    int? totalUnits,
    int? accent,
  }) {
    return BookItem(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      path: path ?? this.path,
      format: format ?? this.format,
      addedAt: addedAt ?? this.addedAt,
      lastOpenedAt: identical(lastOpenedAt, _sentinel) ? this.lastOpenedAt : lastOpenedAt as DateTime?,
      progress: progress ?? this.progress,
      favorite: favorite ?? this.favorite,
      totalUnits: totalUnits ?? this.totalUnits,
      accent: accent ?? this.accent,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'path': path,
      'format': format.name,
      'addedAt': addedAt.toIso8601String(),
      'lastOpenedAt': lastOpenedAt?.toIso8601String(),
      'progress': progress,
      'favorite': favorite,
      'totalUnits': totalUnits,
      'accent': accent,
    };
  }

  factory BookItem.fromJson(Map<String, dynamic> json) {
    return BookItem(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? 'Tanpa Judul',
      author: json['author'] as String? ?? 'Offline file',
      path: json['path'] as String? ?? '',
      format: BookFormat.values.firstWhere(
        (f) => f.name == json['format'],
        orElse: () => BookFormat.unknown,
      ),
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
      lastOpenedAt: DateTime.tryParse(json['lastOpenedAt'] as String? ?? ''),
      progress: ((json['progress'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0).toDouble(),
      favorite: json['favorite'] as bool? ?? false,
      totalUnits: json['totalUnits'] as int? ?? 0,
      accent: json['accent'] as int? ?? 0,
    );
  }
}

const Object _sentinel = Object();

class ReaderBookmark {
  const ReaderBookmark({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.unitIndex,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final int unitIndex;
  final String note;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookId': bookId,
      'bookTitle': bookTitle,
      'unitIndex': unitIndex,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ReaderBookmark.fromJson(Map<String, dynamic> json) {
    return ReaderBookmark(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      bookId: json['bookId'] as String? ?? '',
      bookTitle: json['bookTitle'] as String? ?? 'Buku',
      unitIndex: json['unitIndex'] as int? ?? 0,
      note: json['note'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class ReaderSettings {
  const ReaderSettings({
    required this.themeIndex,
    required this.fontSize,
    required this.lineHeight,
    required this.margin,
    required this.pageCurlHint,
  });

  final int themeIndex;
  final double fontSize;
  final double lineHeight;
  final double margin;
  final bool pageCurlHint;

  ReaderSettings copyWith({
    int? themeIndex,
    double? fontSize,
    double? lineHeight,
    double? margin,
    bool? pageCurlHint,
  }) {
    return ReaderSettings(
      themeIndex: themeIndex ?? this.themeIndex,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      margin: margin ?? this.margin,
      pageCurlHint: pageCurlHint ?? this.pageCurlHint,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeIndex': themeIndex,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'margin': margin,
      'pageCurlHint': pageCurlHint,
    };
  }

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    return ReaderSettings(
      themeIndex: json['themeIndex'] as int? ?? 0,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.55,
      margin: (json['margin'] as num?)?.toDouble() ?? 24,
      pageCurlHint: json['pageCurlHint'] as bool? ?? true,
    );
  }

  static const defaults = ReaderSettings(
    themeIndex: 0,
    fontSize: 18,
    lineHeight: 1.55,
    margin: 24,
    pageCurlHint: true,
  );
}

class ReaderPalette {
  const ReaderPalette({required this.name, required this.background, required this.page, required this.text, required this.muted});
  final String name;
  final Color background;
  final Color page;
  final Color text;
  final Color muted;
}

const List<ReaderPalette> readerPalettes = [
  ReaderPalette(name: 'Paper Glass', background: Color(0xFFEDEAF7), page: Color(0xFFFFFEFA), text: Color(0xFF1C1B20), muted: Color(0xFF6D6875)),
  ReaderPalette(name: 'Warm Sand', background: Color(0xFFEEE1CF), page: Color(0xFFFFF2DC), text: Color(0xFF33281B), muted: Color(0xFF7A6550)),
  ReaderPalette(name: 'Ink Night', background: Color(0xFF0F111A), page: Color(0xFF181B27), text: Color(0xFFE9E8F4), muted: Color(0xFFA7A3B6)),
  ReaderPalette(name: 'Mint Focus', background: Color(0xFFE6F4EF), page: Color(0xFFF6FFFB), text: Color(0xFF10251E), muted: Color(0xFF527266)),
];

class LocalStore {
  static const _booksKey = 'offline_books_v6';
  static const _bookmarksKey = 'offline_bookmarks_v6';
  static const _settingsKey = 'reader_settings_v6';

  static Future<List<BookItem>> loadBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_booksKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => BookItem.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) {
        final aTime = a.lastOpenedAt ?? a.addedAt;
        final bTime = b.lastOpenedAt ?? b.addedAt;
        return bTime.compareTo(aTime);
      });
  }

  static Future<void> saveBooks(List<BookItem> books) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_booksKey, jsonEncode(books.map((e) => e.toJson()).toList()));
  }

  static Future<List<ReaderBookmark>> loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_bookmarksKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => ReaderBookmark.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Future<void> saveBookmarks(List<ReaderBookmark> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bookmarksKey, jsonEncode(bookmarks.map((e) => e.toJson()).toList()));
  }

  static Future<ReaderSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return ReaderSettings.defaults;
    return ReaderSettings.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  static Future<void> saveSettings(ReaderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }
}

class OfflineReaderHome extends StatefulWidget {
  const OfflineReaderHome({super.key});

  @override
  State<OfflineReaderHome> createState() => _OfflineReaderHomeState();
}

class _OfflineReaderHomeState extends State<OfflineReaderHome> {
  List<BookItem> _books = [];
  List<ReaderBookmark> _bookmarks = [];
  ReaderSettings _settings = ReaderSettings.defaults;
  HomeSection _section = HomeSection.dashboard;
  String _search = '';
  bool _grid = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final books = await LocalStore.loadBooks();
    final bookmarks = await LocalStore.loadBookmarks();
    final settings = await LocalStore.loadSettings();
    if (!mounted) return;
    setState(() {
      _books = books;
      _bookmarks = bookmarks;
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _saveBooks() async => LocalStore.saveBooks(_books);

  void _setSection(HomeSection section) {
    Navigator.of(context).maybePop();
    setState(() => _section = section);
  }

  Future<Directory> _bookDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final bookDir = Directory(p.join(dir.path, 'offline_books'));
    if (!bookDir.existsSync()) {
      await bookDir.create(recursive: true);
    }
    return bookDir;
  }

  Future<void> _importBook() async {
    final group = fs.XTypeGroup(
      label: 'Offline book files',
      extensions: const ['pdf', 'epub', 'txt', 'cbz', 'zip'],
      mimeTypes: const [
        'application/pdf',
        'application/epub+zip',
        'text/plain',
        'application/zip',
        'application/x-cbz',
        'application/vnd.comicbook+zip',
      ],
    );

    final picked = await fs.openFile(acceptedTypeGroups: [group]);
    if (picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) {
        _showSnack('File kosong atau tidak bisa dibaca.');
        return;
      }

      final format = _formatFromPath(picked.name);
      if (format == BookFormat.unknown) {
        _showSnack('Format belum didukung. Pakai PDF, EPUB, TXT, atau CBZ/ZIP.');
        return;
      }

      final dir = await _bookDir();
      final safeName = _safeFileName(p.basename(picked.name));
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final dest = File(p.join(dir.path, fileName));
      await dest.writeAsBytes(bytes, flush: true);

      final title = _titleFromFile(picked.name);
      final total = await _estimateTotalUnits(dest.path, format);
      final book = BookItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        author: 'Local offline',
        path: dest.path,
        format: format,
        addedAt: DateTime.now(),
        lastOpenedAt: null,
        progress: 0,
        favorite: false,
        totalUnits: total,
        accent: math.Random().nextInt(_coverColors.length),
      );

      setState(() {
        _books = [book, ..._books];
        _section = HomeSection.library;
      });
      await _saveBooks();
      _showSnack('Buku berhasil masuk ke library offline.');
    } catch (e) {
      _showSnack('Gagal impor: $e');
    }
  }

  Future<void> _openBook(BookItem book, {int? jumpTo}) async {
    if (!book.exists) {
      _showSnack('File buku tidak ditemukan. Mungkin sudah terhapus.');
      return;
    }

    final updated = book.copyWith(lastOpenedAt: DateTime.now());
    _replaceBook(updated);
    await _saveBooks();

    final result = await Navigator.of(context).push<BookItem>(
      MaterialPageRoute(
        builder: (_) => ReaderRouter(
          book: updated,
          settings: _settings,
          initialUnit: jumpTo,
        ),
      ),
    );

    final books = await LocalStore.loadBooks();
    final bookmarks = await LocalStore.loadBookmarks();
    if (!mounted) return;
    setState(() {
      _books = books;
      _bookmarks = bookmarks;
      if (result != null) _replaceBook(result);
    });
  }

  void _replaceBook(BookItem updated) {
    final index = _books.indexWhere((e) => e.id == updated.id);
    if (index == -1) return;
    final next = [..._books];
    next[index] = updated;
    next.sort((a, b) {
      final aTime = a.lastOpenedAt ?? a.addedAt;
      final bTime = b.lastOpenedAt ?? b.addedAt;
      return bTime.compareTo(aTime);
    });
    _books = next;
  }

  Future<void> _toggleFavorite(BookItem book) async {
    setState(() => _replaceBook(book.copyWith(favorite: !book.favorite)));
    await _saveBooks();
  }

  Future<void> _deleteBook(BookItem book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus buku?'),
        content: Text('“${book.title}” akan dihapus dari library dan storage aplikasi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final file = File(book.path);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
    setState(() => _books = _books.where((e) => e.id != book.id).toList());
    await _saveBooks();
  }

  Future<void> _renameBook(BookItem book) async {
    final controller = TextEditingController(text: book.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ubah judul'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Judul buku'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Simpan')),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty) return;
    setState(() => _replaceBook(book.copyWith(title: newTitle)));
    await _saveBooks();
  }

  Future<void> _updateSettings(ReaderSettings settings) async {
    setState(() => _settings = settings);
    await LocalStore.saveSettings(settings);
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  List<BookItem> get _filteredBooks {
    final q = _search.trim().toLowerCase();
    Iterable<BookItem> items = _books;
    if (_section == HomeSection.favorites) {
      items = items.where((e) => e.favorite);
    } else if (_section == HomeSection.continueReading) {
      items = items.where((e) => e.isStarted && !e.isFinished);
    }
    if (q.isNotEmpty) {
      items = items.where((e) => e.title.toLowerCase().contains(q) || e.format.label.toLowerCase().contains(q));
    }
    return items.toList();
  }

  String get _title {
    switch (_section) {
      case HomeSection.dashboard:
        return 'Babeh Reader';
      case HomeSection.library:
        return 'Library Offline';
      case HomeSection.continueReading:
        return 'Lanjut Baca';
      case HomeSection.favorites:
        return 'Favorit';
      case HomeSection.bookmarks:
        return 'Markah & Catatan';
      case HomeSection.collections:
        return 'Koleksi Pintar';
      case HomeSection.statistics:
        return 'Statistik';
      case HomeSection.settings:
        return 'Pengaturan';
      case HomeSection.about:
        return 'Tentang';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      drawer: _AppDrawer(
        selected: _section,
        books: _books,
        bookmarks: _bookmarks,
        onSelect: _setSection,
        onImport: _importBook,
      ),
      appBar: AppBar(
        title: Text(_title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_section == HomeSection.library || _section == HomeSection.favorites || _section == HomeSection.continueReading)
            IconButton(
              tooltip: _grid ? 'Tampilan list' : 'Tampilan grid',
              onPressed: () => setState(() => _grid = !_grid),
              icon: Icon(_grid ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2),
            ),
          IconButton.filledTonal(
            tooltip: 'Impor buku offline',
            onPressed: _importBook,
            icon: const Icon(CupertinoIcons.plus),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primary.withOpacity(0.06),
                          scheme.secondaryContainer.withOpacity(0.12),
                          scheme.surface,
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(child: _buildSection()),
              ],
            ),
    );
  }

  Widget _buildSection() {
    switch (_section) {
      case HomeSection.dashboard:
        return _DashboardView(
          books: _books,
          bookmarks: _bookmarks,
          onOpen: _openBook,
          onImport: _importBook,
          onSection: _setSection,
        );
      case HomeSection.library:
      case HomeSection.continueReading:
      case HomeSection.favorites:
        return _LibraryView(
          books: _filteredBooks,
          search: _search,
          grid: _grid,
          emptyTitle: _section == HomeSection.favorites
              ? 'Belum ada buku favorit'
              : _section == HomeSection.continueReading
                  ? 'Belum ada bacaan berjalan'
                  : 'Library masih kosong',
          onSearch: (v) => setState(() => _search = v),
          onOpen: _openBook,
          onFavorite: _toggleFavorite,
          onDelete: _deleteBook,
          onRename: _renameBook,
          onImport: _importBook,
        );
      case HomeSection.bookmarks:
        return _BookmarksView(
          bookmarks: _bookmarks,
          books: _books,
          onOpen: (bookmark) {
            final book = _books.where((e) => e.id == bookmark.bookId).firstOrNull;
            if (book == null) {
              _showSnack('Buku untuk markah ini sudah tidak ada.');
              return;
            }
            _openBook(book, jumpTo: bookmark.unitIndex);
          },
          onDelete: (bookmark) async {
            final next = _bookmarks.where((e) => e.id != bookmark.id).toList();
            setState(() => _bookmarks = next);
            await LocalStore.saveBookmarks(next);
          },
        );
      case HomeSection.collections:
        return _CollectionsView(books: _books, onOpen: _openBook, onSection: _setSection);
      case HomeSection.statistics:
        return _StatisticsView(books: _books, bookmarks: _bookmarks);
      case HomeSection.settings:
        return _SettingsView(settings: _settings, onChanged: _updateSettings);
      case HomeSection.about:
        return const _AboutView();
    }
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.selected,
    required this.books,
    required this.bookmarks,
    required this.onSelect,
    required this.onImport,
  });

  final HomeSection selected;
  final List<BookItem> books;
  final List<ReaderBookmark> bookmarks;
  final ValueChanged<HomeSection> onSelect;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inProgress = books.where((e) => e.isStarted && !e.isFinished).length;
    final fav = books.where((e) => e.favorite).length;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  colors: [scheme.primaryContainer, scheme.secondaryContainer],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primary,
                    child: Icon(CupertinoIcons.book_fill, color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 14),
                  Text('Babeh Reader', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('Full offline • modern shelf', style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _DrawerTile(selected: selected == HomeSection.dashboard, icon: CupertinoIcons.house, title: 'Beranda', onTap: () => onSelect(HomeSection.dashboard)),
                  _DrawerTile(selected: selected == HomeSection.library, icon: CupertinoIcons.square_grid_2x2, title: 'Library Offline', trailing: books.length.toString(), onTap: () => onSelect(HomeSection.library)),
                  _DrawerTile(selected: selected == HomeSection.continueReading, icon: CupertinoIcons.play_circle, title: 'Lanjut Baca', trailing: inProgress.toString(), onTap: () => onSelect(HomeSection.continueReading)),
                  _DrawerTile(selected: selected == HomeSection.favorites, icon: CupertinoIcons.heart, title: 'Favorit', trailing: fav.toString(), onTap: () => onSelect(HomeSection.favorites)),
                  _DrawerTile(selected: selected == HomeSection.bookmarks, icon: CupertinoIcons.bookmark, title: 'Markah & Catatan', trailing: bookmarks.length.toString(), onTap: () => onSelect(HomeSection.bookmarks)),
                  _DrawerTile(selected: selected == HomeSection.collections, icon: CupertinoIcons.rectangle_grid_1x2, title: 'Koleksi Pintar', onTap: () => onSelect(HomeSection.collections)),
                  const Divider(height: 28),
                  _DrawerTile(selected: selected == HomeSection.statistics, icon: CupertinoIcons.chart_bar_alt_fill, title: 'Statistik', onTap: () => onSelect(HomeSection.statistics)),
                  _DrawerTile(selected: selected == HomeSection.settings, icon: CupertinoIcons.slider_horizontal_3, title: 'Pengaturan Reader', onTap: () => onSelect(HomeSection.settings)),
                  _DrawerTile(selected: selected == HomeSection.about, icon: CupertinoIcons.info_circle, title: 'Tentang', onTap: () => onSelect(HomeSection.about)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onImport,
                  icon: const Icon(CupertinoIcons.plus),
                  label: const Text('Impor Buku'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({required this.selected, required this.icon, required this.title, required this.onTap, this.trailing});
  final bool selected;
  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: trailing == null
          ? null
          : Badge(
              label: Text(trailing!),
              backgroundColor: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
      onTap: onTap,
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({required this.books, required this.bookmarks, required this.onOpen, required this.onImport, required this.onSection});
  final List<BookItem> books;
  final List<ReaderBookmark> bookmarks;
  final ValueChanged<BookItem> onOpen;
  final VoidCallback onImport;
  final ValueChanged<HomeSection> onSection;

  @override
  Widget build(BuildContext context) {
    final latest = books.where((e) => e.isStarted && !e.isFinished).toList();
    final recent = books.take(8).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        _HeroPanel(books: books, onImport: onImport),
        const SizedBox(height: 18),
        _QuickActions(onImport: onImport, onSection: onSection),
        const SizedBox(height: 22),
        _SectionHeader(
          title: 'Lanjut dari halaman terakhir',
          action: latest.isEmpty ? null : 'Lihat semua',
          onAction: () => onSection(HomeSection.continueReading),
        ),
        const SizedBox(height: 10),
        if (latest.isEmpty)
          _EmptyCard(title: 'Belum ada progress', subtitle: 'Buka buku lalu geser halaman untuk menyimpan progress otomatis.', icon: CupertinoIcons.play_circle)
        else
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) => _ContinueCard(book: latest[index], onTap: () => onOpen(latest[index])),
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemCount: math.min(latest.length, 8),
            ),
          ),
        const SizedBox(height: 24),
        _SectionHeader(title: 'Shelf terbaru', action: recent.isEmpty ? null : 'Library', onAction: () => onSection(HomeSection.library)),
        const SizedBox(height: 10),
        if (recent.isEmpty)
          _EmptyImport(onImport: onImport)
        else
          ...recent.map((book) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BookListTile(book: book, onOpen: () => onOpen(book)),
              )),
        const SizedBox(height: 10),
        _OfflineInfoCard(bookmarks: bookmarks.length),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.books, required this.onImport});
  final List<BookItem> books;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final finished = books.where((e) => e.isFinished).length;
    final reading = books.where((e) => e.isStarted && !e.isFinished).length;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary, const Color(0xFF23233A)],
        ),
        boxShadow: [BoxShadow(color: scheme.primary.withOpacity(0.18), blurRadius: 30, offset: const Offset(0, 18))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.sparkles, color: scheme.onPrimary),
              const SizedBox(width: 8),
              Text('Offline Reading Space', style: TextStyle(color: scheme.onPrimary.withOpacity(0.9), fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Baca tanpa internet, dengan rak modern dan halaman geser.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900, height: 1.08),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeroStat(label: 'Buku', value: '${books.length}'),
              _HeroStat(label: 'Dibaca', value: '$reading'),
              _HeroStat(label: 'Selesai', value: '$finished'),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(onPressed: onImport, icon: const Icon(CupertinoIcons.tray_arrow_down), label: const Text('Tambah buku offline')),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.17),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onImport, required this.onSection});
  final VoidCallback onImport;
  final ValueChanged<HomeSection> onSection;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _ActionPill(icon: CupertinoIcons.plus_app, title: 'Impor', onTap: onImport)),
        const SizedBox(width: 10),
        Expanded(child: _ActionPill(icon: CupertinoIcons.bookmark, title: 'Markah', onTap: () => onSection(HomeSection.bookmarks))),
        const SizedBox(width: 10),
        Expanded(child: _ActionPill(icon: CupertinoIcons.slider_horizontal_3, title: 'Tema', onTap: () => onSection(HomeSection.settings))),
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon),
              const SizedBox(height: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryView extends StatelessWidget {
  const _LibraryView({
    required this.books,
    required this.search,
    required this.grid,
    required this.emptyTitle,
    required this.onSearch,
    required this.onOpen,
    required this.onFavorite,
    required this.onDelete,
    required this.onRename,
    required this.onImport,
  });

  final List<BookItem> books;
  final String search;
  final bool grid;
  final String emptyTitle;
  final ValueChanged<String> onSearch;
  final ValueChanged<BookItem> onOpen;
  final ValueChanged<BookItem> onFavorite;
  final ValueChanged<BookItem> onDelete;
  final ValueChanged<BookItem> onRename;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: TextField(
            controller: TextEditingController(text: search)..selection = TextSelection.collapsed(offset: search.length),
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: 'Cari judul atau format...',
              prefixIcon: const Icon(CupertinoIcons.search),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: books.isEmpty
              ? Center(child: _EmptyCard(title: emptyTitle, subtitle: 'Tekan tombol impor untuk menambahkan file lokal.', icon: CupertinoIcons.tray_arrow_down, actionText: 'Impor buku', onAction: onImport))
              : grid
                  ? GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisExtent: 278,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemBuilder: (context, index) {
                        final book = books[index];
                        return _BookGridCard(
                          book: book,
                          onOpen: () => onOpen(book),
                          onFavorite: () => onFavorite(book),
                          onDelete: () => onDelete(book),
                          onRename: () => onRename(book),
                        );
                      },
                      itemCount: books.length,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      itemBuilder: (context, index) {
                        final book = books[index];
                        return _BookListTile(
                          book: book,
                          onOpen: () => onOpen(book),
                          onFavorite: () => onFavorite(book),
                          onDelete: () => onDelete(book),
                          onRename: () => onRename(book),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemCount: books.length,
                    ),
        ),
      ],
    );
  }
}

class _BookGridCard extends StatelessWidget {
  const _BookGridCard({required this.book, required this.onOpen, required this.onFavorite, required this.onDelete, required this.onRename});
  final BookItem book;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final color = _coverColors[book.accent % _coverColors.length];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ModernCover(book: book, color: color),
              ),
              const SizedBox(height: 10),
              Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, height: 1.1)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _TinyProgress(progress: book.progress)),
                  const SizedBox(width: 8),
                  Text('${(book.progress * 100).round()}%', style: Theme.of(context).textTheme.labelSmall),
                  _BookMenu(book: book, onFavorite: onFavorite, onDelete: onDelete, onRename: onRename),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModernCover extends StatelessWidget {
  const _ModernCover({required this.book, required this.color});
  final BookItem book;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.35)!],
        ),
        boxShadow: [BoxShadow(color: color.withOpacity(0.23), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Stack(
        children: [
          Positioned(right: -10, bottom: -12, child: Icon(book.format.icon, color: Colors.white.withOpacity(0.15), size: 96)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(999)),
                child: Text(book.format.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
              ),
              const Spacer(),
              Text(_initials(book.title), style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -2)),
            ],
          ),
          if (book.favorite)
            const Positioned(right: 0, top: 0, child: Icon(CupertinoIcons.heart_fill, color: Colors.white)),
        ],
      ),
    );
  }
}

class _BookListTile extends StatelessWidget {
  const _BookListTile({required this.book, required this.onOpen, this.onFavorite, this.onDelete, this.onRename});
  final BookItem book;
  final VoidCallback onOpen;
  final VoidCallback? onFavorite;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final color = _coverColors[book.accent % _coverColors.length];
    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SizedBox(width: 72, height: 96, child: _ModernCover(book: book, color: color)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 6),
                    Text('${book.format.label} • ${book.exists ? 'offline ready' : 'file hilang'}', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Row(children: [Expanded(child: _TinyProgress(progress: book.progress)), const SizedBox(width: 8), Text('${(book.progress * 100).round()}%')]),
                  ],
                ),
              ),
              if (onFavorite != null && onDelete != null && onRename != null)
                _BookMenu(book: book, onFavorite: onFavorite!, onDelete: onDelete!, onRename: onRename!),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookMenu extends StatelessWidget {
  const _BookMenu({required this.book, required this.onFavorite, required this.onDelete, required this.onRename});
  final BookItem book;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 18),
      onSelected: (value) {
        if (value == 'fav') onFavorite();
        if (value == 'rename') onRename();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'fav', child: Text(book.favorite ? 'Hapus favorit' : 'Jadikan favorit')),
        const PopupMenuItem(value: 'rename', child: Text('Ubah judul')),
        const PopupMenuItem(value: 'delete', child: Text('Hapus')),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.book, required this.onTap});
  final BookItem book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 172,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(book.format.icon, size: 18), const SizedBox(width: 6), Text(book.format.label, style: const TextStyle(fontWeight: FontWeight.w800))]),
                const Spacer(),
                Text(book.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, height: 1.1)),
                const SizedBox(height: 12),
                _TinyProgress(progress: book.progress),
                const SizedBox(height: 8),
                Text('Lanjut ${(book.progress * 100).round()}%', style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TinyProgress extends StatelessWidget {
  const _TinyProgress({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        minHeight: 7,
        value: progress.clamp(0.0, 1.0).toDouble(),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, required this.subtitle, required this.icon, this.actionText, this.onAction});
  final String title;
  final String subtitle;
  final IconData icon;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            if (actionText != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionText!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyImport extends StatelessWidget {
  const _EmptyImport({required this.onImport});
  final VoidCallback onImport;
  @override
  Widget build(BuildContext context) {
    return _EmptyCard(
      title: 'Belum ada buku offline',
      subtitle: 'Impor file PDF, EPUB, TXT, atau CBZ dari penyimpanan HP. Setelah masuk, buku bisa dibaca tanpa internet.',
      icon: CupertinoIcons.tray_arrow_down,
      actionText: 'Impor sekarang',
      onAction: onImport,
    );
  }
}

class _OfflineInfoCard extends StatelessWidget {
  const _OfflineInfoCard({required this.bookmarks});
  final int bookmarks;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(CupertinoIcons.wifi_slash),
            const SizedBox(width: 12),
            Expanded(child: Text('Mode full offline aktif. Tidak ada katalog online, tidak ada sinkronisasi, dan tidak ada koneksi internet dari aplikasi. Markah tersimpan: $bookmarks')),
          ],
        ),
      ),
    );
  }
}

class _BookmarksView extends StatelessWidget {
  const _BookmarksView({required this.bookmarks, required this.books, required this.onOpen, required this.onDelete});
  final List<ReaderBookmark> bookmarks;
  final List<BookItem> books;
  final ValueChanged<ReaderBookmark> onOpen;
  final ValueChanged<ReaderBookmark> onDelete;

  @override
  Widget build(BuildContext context) {
    if (bookmarks.isEmpty) {
      return const Center(child: _EmptyCard(title: 'Belum ada markah', subtitle: 'Saat membaca, tekan ikon bookmark untuk menandai halaman.', icon: CupertinoIcons.bookmark));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemBuilder: (context, index) {
        final b = bookmarks[index];
        final bookExists = books.any((e) => e.id == b.bookId);
        return Card(
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            leading: Icon(bookExists ? CupertinoIcons.bookmark_fill : CupertinoIcons.exclamationmark_triangle),
            title: Text(b.bookTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('Halaman/unit ${b.unitIndex + 1}${b.note.isEmpty ? '' : ' • ${b.note}'}'),
            onTap: () => onOpen(b),
            trailing: IconButton(icon: const Icon(CupertinoIcons.delete), onPressed: () => onDelete(b)),
          ),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: bookmarks.length,
    );
  }
}

class _CollectionsView extends StatelessWidget {
  const _CollectionsView({required this.books, required this.onOpen, required this.onSection});
  final List<BookItem> books;
  final ValueChanged<BookItem> onOpen;
  final ValueChanged<HomeSection> onSection;

  @override
  Widget build(BuildContext context) {
    final collections = <_SmartCollection>[
      _SmartCollection('Baru Ditambahkan', CupertinoIcons.clock, books.take(12).toList()),
      _SmartCollection('Bacaan Belum Selesai', CupertinoIcons.play_circle, books.where((e) => e.isStarted && !e.isFinished).toList()),
      _SmartCollection('PDF Desk', CupertinoIcons.doc_richtext, books.where((e) => e.format == BookFormat.pdf).toList()),
      _SmartCollection('Text Flow', CupertinoIcons.text_alignleft, books.where((e) => e.format == BookFormat.txt || e.format == BookFormat.epub).toList()),
      _SmartCollection('Comic Strip', CupertinoIcons.photo_on_rectangle, books.where((e) => e.format == BookFormat.cbz).toList()),
      _SmartCollection('Favorit', CupertinoIcons.heart, books.where((e) => e.favorite).toList()),
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemBuilder: (context, index) {
        final c = collections[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(c.icon),
                    const SizedBox(width: 10),
                    Expanded(child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
                    Badge(label: Text('${c.books.length}')),
                  ],
                ),
                const SizedBox(height: 14),
                if (c.books.isEmpty)
                  Text('Belum ada item.', style: Theme.of(context).textTheme.bodySmall)
                else
                  SizedBox(
                    height: 116,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, i) {
                        final book = c.books[i];
                        return GestureDetector(
                          onTap: () => onOpen(book),
                          child: SizedBox(width: 80, child: _ModernCover(book: book, color: _coverColors[book.accent % _coverColors.length])),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemCount: math.min(c.books.length, 12),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: collections.length,
    );
  }
}

class _SmartCollection {
  const _SmartCollection(this.title, this.icon, this.books);
  final String title;
  final IconData icon;
  final List<BookItem> books;
}

class _StatisticsView extends StatelessWidget {
  const _StatisticsView({required this.books, required this.bookmarks});
  final List<BookItem> books;
  final List<ReaderBookmark> bookmarks;

  @override
  Widget build(BuildContext context) {
    final finished = books.where((e) => e.isFinished).length;
    final reading = books.where((e) => e.isStarted && !e.isFinished).length;
    final double avg = books.isEmpty ? 0.0 : books.map((e) => e.progress).reduce((a, b) => a + b) / books.length;
    final pdf = books.where((e) => e.format == BookFormat.pdf).length;
    final text = books.where((e) => e.format == BookFormat.txt || e.format == BookFormat.epub).length;
    final cbz = books.where((e) => e.format == BookFormat.cbz).length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: _StatCard(title: 'Total buku', value: '${books.length}', icon: CupertinoIcons.book)),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(title: 'Dibaca', value: '$reading', icon: CupertinoIcons.play_circle)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _StatCard(title: 'Selesai', value: '$finished', icon: CupertinoIcons.check_mark_circled)),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(title: 'Markah', value: '${bookmarks.length}', icon: CupertinoIcons.bookmark)),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Progress library', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 14),
                _TinyProgress(progress: avg),
                const SizedBox(height: 8),
                Text('Rata-rata ${(avg * 100).round()}% dari semua buku.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Komposisi format', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                _FormatRow(label: 'PDF', value: pdf, total: books.length),
                _FormatRow(label: 'EPUB/TXT', value: text, total: books.length),
                _FormatRow(label: 'CBZ', value: cbz, total: books.length),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 12),
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            Text(title),
          ],
        ),
      ),
    );
  }
}

class _FormatRow extends StatelessWidget {
  const _FormatRow({required this.label, required this.value, required this.total});
  final String label;
  final int value;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: _TinyProgress(progress: progress)),
          const SizedBox(width: 10),
          Text('$value'),
        ],
      ),
    );
  }
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({required this.settings, required this.onChanged});
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tema baca', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < readerPalettes.length; i++)
                      ChoiceChip(
                        selected: settings.themeIndex == i,
                        label: Text(readerPalettes[i].name),
                        avatar: CircleAvatar(backgroundColor: readerPalettes[i].page),
                        onSelected: (_) => onChanged(settings.copyWith(themeIndex: i)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tipografi', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                _SliderSetting(label: 'Ukuran font', value: settings.fontSize, min: 14, max: 28, divisions: 14, onChanged: (v) => onChanged(settings.copyWith(fontSize: v))),
                _SliderSetting(label: 'Jarak baris', value: settings.lineHeight, min: 1.2, max: 2.0, divisions: 8, onChanged: (v) => onChanged(settings.copyWith(lineHeight: v))),
                _SliderSetting(label: 'Margin halaman', value: settings.margin, min: 12, max: 40, divisions: 14, onChanged: (v) => onChanged(settings.copyWith(margin: v))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            value: settings.pageCurlHint,
            onChanged: (v) => onChanged(settings.copyWith(pageCurlHint: v)),
            title: const Text('Petunjuk geser halaman', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Menampilkan hint kecil saat masuk reader.'),
            secondary: const Icon(CupertinoIcons.hand_draw),
          ),
        ),
      ],
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({required this.label, required this.value, required this.min, required this.max, required this.divisions, required this.onChanged});
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(children: [Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))), Text(value.toStringAsFixed(1))]),
        Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, divisions: divisions, onChanged: onChanged),
      ],
    );
  }
}

class _AboutView extends StatelessWidget {
  const _AboutView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        _EmptyCard(
          title: 'Babeh Reader v6 Offline',
          subtitle: 'Aplikasi baca buku lokal dengan konsep modern: hamburger menu, smart collection, progress otomatis, markah, dan halaman geser seperti buku. Tidak memakai katalog online.',
          icon: CupertinoIcons.info_circle,
        ),
      ],
    );
  }
}

class ReaderRouter extends StatelessWidget {
  const ReaderRouter({super.key, required this.book, required this.settings, this.initialUnit});
  final BookItem book;
  final ReaderSettings settings;
  final int? initialUnit;

  @override
  Widget build(BuildContext context) {
    switch (book.format) {
      case BookFormat.pdf:
        return PdfOfflineReader(book: book, initialPage: initialUnit);
      case BookFormat.cbz:
        return ComicOfflineReader(book: book, initialPage: initialUnit);
      case BookFormat.epub:
      case BookFormat.txt:
        return TextOfflineReader(book: book, settings: settings, initialPage: initialUnit);
      case BookFormat.unknown:
        return Scaffold(appBar: AppBar(title: Text(book.title)), body: const Center(child: Text('Format belum didukung.')));
    }
  }
}

class TextOfflineReader extends StatefulWidget {
  const TextOfflineReader({super.key, required this.book, required this.settings, this.initialPage});
  final BookItem book;
  final ReaderSettings settings;
  final int? initialPage;

  @override
  State<TextOfflineReader> createState() => _TextOfflineReaderState();
}

class _TextOfflineReaderState extends State<TextOfflineReader> {
  late ReaderSettings _settings;
  late PageController _controller;
  List<String> _pages = [];
  int _page = 0;
  bool _loading = true;
  String? _error;
  Timer? _saveTimer;
  bool _showChrome = true;

  ReaderPalette get _palette => readerPalettes[_settings.themeIndex.clamp(0, readerPalettes.length - 1).toInt()];

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    final initial = widget.initialPage ?? _progressToPage(widget.book.progress, widget.book.totalUnits);
    _page = math.max(0, initial);
    _controller = PageController(initialPage: _page);
    _loadText();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadText() async {
    try {
      final text = widget.book.format == BookFormat.epub ? await _readEpubText(widget.book.path) : await _readPlainText(widget.book.path);
      final pages = _paginate(text, _settings);
      if (!mounted) return;
      setState(() {
        _pages = pages.isEmpty ? ['File tidak memiliki teks yang bisa dibaca.'] : pages;
        _page = _page.clamp(0, math.max(0, _pages.length - 1)).toInt();
        _controller = PageController(initialPage: _page);
        _loading = false;
      });
      await _saveProgress();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _repaginate() async {
    final oldProgress = _pages.isEmpty ? widget.book.progress : (_page + 1) / _pages.length;
    setState(() => _loading = true);
    await LocalStore.saveSettings(_settings);
    try {
      final text = widget.book.format == BookFormat.epub ? await _readEpubText(widget.book.path) : await _readPlainText(widget.book.path);
      final pages = _paginate(text, _settings);
      final target = _progressToPage(oldProgress, pages.length);
      if (!mounted) return;
      setState(() {
        _pages = pages.isEmpty ? ['File tidak memiliki teks yang bisa dibaca.'] : pages;
        _page = target.clamp(0, math.max(0, _pages.length - 1)).toInt();
        _controller = PageController(initialPage: _page);
        _loading = false;
      });
      await _saveProgress();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveProgress() async {
    if (_pages.isEmpty) return;
    final books = await LocalStore.loadBooks();
    final progress = ((_page + 1) / _pages.length).clamp(0.0, 1.0).toDouble();
    final index = books.indexWhere((e) => e.id == widget.book.id);
    if (index != -1) {
      books[index] = books[index].copyWith(progress: progress, lastOpenedAt: DateTime.now(), totalUnits: _pages.length);
      await LocalStore.saveBooks(books);
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _saveProgress);
  }

  Future<void> _addBookmark() async {
    final bookmarks = await LocalStore.loadBookmarks();
    final excerpt = _pages.isEmpty ? '' : _pages[_page].replaceAll(RegExp(r'\s+'), ' ').trim();
    final note = excerpt.length > 80 ? '${excerpt.substring(0, 80)}…' : excerpt;
    bookmarks.insert(
      0,
      ReaderBookmark(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        bookId: widget.book.id,
        bookTitle: widget.book.title,
        unitIndex: _page,
        note: note,
        createdAt: DateTime.now(),
      ),
    );
    await LocalStore.saveBookmarks(bookmarks);
    _snack('Markah disimpan di halaman ${_page + 1}.');
  }

  Future<void> _openSettings() async {
    final result = await showModalBottomSheet<ReaderSettings>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ReaderSettingsSheet(settings: _settings),
    );
    if (result == null) return;
    setState(() => _settings = result);
    await _repaginate();
  }

  Future<void> _searchInside() async {
    final query = await showSearch<String?>(context: context, delegate: _TextSearchDelegate(_pages));
    if (query == null || query.isEmpty) return;
    final index = int.tryParse(query);
    if (index == null) return;
    _controller.jumpToPage(index);
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async => _saveProgress(),
      child: Scaffold(
        backgroundColor: _palette.background,
        body: SafeArea(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: _palette.text))
              : _error != null
                  ? _ReaderError(title: widget.book.title, error: _error!)
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () => setState(() => _showChrome = !_showChrome),
                            child: PageView.builder(
                              controller: _controller,
                              onPageChanged: (value) {
                                setState(() => _page = value);
                                _scheduleSave();
                              },
                              itemCount: _pages.length,
                              itemBuilder: (context, index) => _TextPage(
                                text: _pages[index],
                                page: index,
                                total: _pages.length,
                                settings: _settings,
                                palette: _palette,
                              ),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 220),
                          left: 12,
                          right: 12,
                          top: _showChrome ? 8 : -90,
                          child: _ReaderTopBar(
                            title: widget.book.title,
                            palette: _palette,
                            onBack: () async {
                              await _saveProgress();
                              if (mounted) Navigator.pop(context);
                            },
                            actions: [
                              IconButton(onPressed: _searchInside, icon: Icon(CupertinoIcons.search, color: _palette.text)),
                              IconButton(onPressed: _addBookmark, icon: Icon(CupertinoIcons.bookmark, color: _palette.text)),
                              IconButton(onPressed: _openSettings, icon: Icon(CupertinoIcons.slider_horizontal_3, color: _palette.text)),
                            ],
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 220),
                          left: 20,
                          right: 20,
                          bottom: _showChrome ? 16 : -90,
                          child: _ReaderBottomBar(
                            palette: _palette,
                            page: _page,
                            total: _pages.length,
                            onChanged: (v) {
                              final target = v.round().clamp(0, math.max(0, _pages.length - 1)).toInt();
                              _controller.jumpToPage(target);
                            },
                          ),
                        ),
                        if (widget.settings.pageCurlHint)
                          Positioned(
                            right: 18,
                            top: MediaQuery.of(context).size.height * 0.48,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(color: _palette.page.withOpacity(0.7), borderRadius: BorderRadius.circular(999)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(CupertinoIcons.chevron_left_slash_chevron_right, size: 16, color: _palette.muted),
                                      const SizedBox(width: 5),
                                      Text('geser', style: TextStyle(color: _palette.muted, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
        ),
      ),
    );
  }
}

class _TextPage extends StatelessWidget {
  const _TextPage({required this.text, required this.page, required this.total, required this.settings, required this.palette});
  final String text;
  final int page;
  final int total;
  final ReaderSettings settings;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 82, 12, 78),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.page,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, 12))],
        ),
        child: Padding(
          padding: EdgeInsets.all(settings.margin),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: settings.fontSize,
                      height: settings.lineHeight,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('${page + 1} / $total', style: TextStyle(color: palette.muted, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({required this.title, required this.palette, required this.onBack, required this.actions});
  final String title;
  final ReaderPalette palette;
  final VoidCallback onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.page.withOpacity(0.92),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(onPressed: onBack, icon: Icon(CupertinoIcons.chevron_back, color: palette.text)),
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.text, fontWeight: FontWeight.w900))),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({required this.palette, required this.page, required this.total, required this.onChanged});
  final ReaderPalette palette;
  final int page;
  final int total;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.page.withOpacity(0.92),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('${page + 1}', style: TextStyle(color: palette.text, fontWeight: FontWeight.w900)),
                Expanded(
                  child: Slider(
                    value: total <= 1 ? 0.0 : page.toDouble().clamp(0, total - 1).toDouble(),
                    min: 0,
                    max: math.max(0, total - 1).toDouble(),
                    divisions: total > 1 && total < 800 ? total - 1 : null,
                    onChanged: total <= 1 ? null : onChanged,
                  ),
                ),
                Text('$total', style: TextStyle(color: palette.text, fontWeight: FontWeight.w900)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderSettingsSheet extends StatefulWidget {
  const _ReaderSettingsSheet({required this.settings});
  final ReaderSettings settings;

  @override
  State<_ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<_ReaderSettingsSheet> {
  late ReaderSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Atur halaman', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < readerPalettes.length; i++)
                  ChoiceChip(
                    selected: _settings.themeIndex == i,
                    label: Text(readerPalettes[i].name),
                    onSelected: (_) => setState(() => _settings = _settings.copyWith(themeIndex: i)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _SliderSetting(label: 'Font', value: _settings.fontSize, min: 14, max: 28, divisions: 14, onChanged: (v) => setState(() => _settings = _settings.copyWith(fontSize: v))),
            _SliderSetting(label: 'Line height', value: _settings.lineHeight, min: 1.2, max: 2.0, divisions: 8, onChanged: (v) => setState(() => _settings = _settings.copyWith(lineHeight: v))),
            _SliderSetting(label: 'Margin', value: _settings.margin, min: 12, max: 40, divisions: 14, onChanged: (v) => setState(() => _settings = _settings.copyWith(margin: v))),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context, _settings), child: const Text('Terapkan'))),
          ],
        ),
      ),
    );
  }
}

class _TextSearchDelegate extends SearchDelegate<String?> {
  _TextSearchDelegate(this.pages);
  final List<String> pages;

  @override
  String get searchFieldLabel => 'Cari di dalam buku...';

  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(onPressed: () => query = '', icon: const Icon(CupertinoIcons.xmark))];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(onPressed: () => close(context, null), icon: const Icon(CupertinoIcons.chevron_back));

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const Center(child: Text('Ketik kata yang mau dicari.'));
    final results = <int>[];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].toLowerCase().contains(q)) results.add(i);
      if (results.length >= 80) break;
    }
    if (results.isEmpty) return const Center(child: Text('Tidak ketemu.'));
    return ListView.separated(
      itemBuilder: (context, index) {
        final pageIndex = results[index];
        final text = pages[pageIndex].replaceAll(RegExp(r'\s+'), ' ').trim();
        return ListTile(
          title: Text('Halaman ${pageIndex + 1}'),
          subtitle: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => close(context, '$pageIndex'),
        );
      },
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemCount: results.length,
    );
  }
}

class ComicOfflineReader extends StatefulWidget {
  const ComicOfflineReader({super.key, required this.book, this.initialPage});
  final BookItem book;
  final int? initialPage;

  @override
  State<ComicOfflineReader> createState() => _ComicOfflineReaderState();
}

class _ComicOfflineReaderState extends State<ComicOfflineReader> {
  List<Uint8List> _images = [];
  late PageController _controller;
  int _page = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage ?? _progressToPage(widget.book.progress, widget.book.totalUnits);
    _controller = PageController(initialPage: math.max(0, _page));
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.book.path).readAsBytes();
      final zip = archive.ZipDecoder().decodeBytes(bytes);
      final files = zip.files.where((f) {
        final n = f.name.toLowerCase();
        return f.isFile && (n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') || n.endsWith('.webp'));
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      final images = <Uint8List>[];
      for (final file in files) {
        final data = file.readBytes();
        if (data == null) continue;
        images.add(Uint8List.fromList(data));
      }
      if (!mounted) return;
      setState(() {
        _images = images;
        _page = _page.clamp(0, math.max(0, images.length - 1)).toInt();
        _controller = PageController(initialPage: _page);
        _loading = false;
      });
      await _saveProgress();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveProgress() async {
    if (_images.isEmpty) return;
    final books = await LocalStore.loadBooks();
    final index = books.indexWhere((e) => e.id == widget.book.id);
    if (index != -1) {
      books[index] = books[index].copyWith(progress: ((_page + 1) / _images.length).clamp(0.0, 1.0).toDouble(), lastOpenedAt: DateTime.now(), totalUnits: _images.length);
      await LocalStore.saveBooks(books);
    }
  }

  Future<void> _addBookmark() async {
    final bookmarks = await LocalStore.loadBookmarks();
    bookmarks.insert(
      0,
      ReaderBookmark(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        bookId: widget.book.id,
        bookTitle: widget.book.title,
        unitIndex: _page,
        note: 'Panel ${_page + 1}',
        createdAt: DateTime.now(),
      ),
    );
    await LocalStore.saveBookmarks(bookmarks);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Markah panel ${_page + 1} disimpan.')));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async => _saveProgress(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          foregroundColor: Colors.white,
          backgroundColor: Colors.black,
          title: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [IconButton(onPressed: _addBookmark, icon: const Icon(CupertinoIcons.bookmark))],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ReaderError(title: widget.book.title, error: _error!)
                : _images.isEmpty
                    ? const Center(child: Text('Tidak ada gambar di file CBZ/ZIP.', style: TextStyle(color: Colors.white)))
                    : Column(
                        children: [
                          Expanded(
                            child: PageView.builder(
                              controller: _controller,
                              onPageChanged: (value) {
                                setState(() => _page = value);
                                _saveProgress();
                              },
                              itemCount: _images.length,
                              itemBuilder: (context, index) => InteractiveViewer(
                                child: Center(child: Image.memory(_images[index], fit: BoxFit.contain, gaplessPlayback: true)),
                              ),
                            ),
                          ),
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                              child: Row(
                                children: [
                                  Text('${_page + 1}', style: const TextStyle(color: Colors.white)),
                                  Expanded(
                                    child: Slider(
                                      value: _page.toDouble(),
                                      min: 0,
                                      max: math.max(0, _images.length - 1).toDouble(),
                                      onChanged: (v) => _controller.jumpToPage(v.round()),
                                    ),
                                  ),
                                  Text('${_images.length}', style: const TextStyle(color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}

class PdfOfflineReader extends StatefulWidget {
  const PdfOfflineReader({super.key, required this.book, this.initialPage});
  final BookItem book;
  final int? initialPage;

  @override
  State<PdfOfflineReader> createState() => _PdfOfflineReaderState();
}

class _PdfOfflineReaderState extends State<PdfOfflineReader> {
  int _page = 0;
  int _pages = 0;
  PDFViewController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage ?? _progressToPage(widget.book.progress, widget.book.totalUnits);
  }

  Future<void> _saveProgress() async {
    if (_pages <= 0) return;
    final books = await LocalStore.loadBooks();
    final index = books.indexWhere((e) => e.id == widget.book.id);
    if (index != -1) {
      books[index] = books[index].copyWith(progress: ((_page + 1) / _pages).clamp(0.0, 1.0).toDouble(), lastOpenedAt: DateTime.now(), totalUnits: _pages);
      await LocalStore.saveBooks(books);
    }
  }

  Future<void> _addBookmark() async {
    final bookmarks = await LocalStore.loadBookmarks();
    bookmarks.insert(
      0,
      ReaderBookmark(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        bookId: widget.book.id,
        bookTitle: widget.book.title,
        unitIndex: _page,
        note: 'PDF halaman ${_page + 1}',
        createdAt: DateTime.now(),
      ),
    );
    await LocalStore.saveBookmarks(bookmarks);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Markah PDF halaman ${_page + 1} disimpan.')));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async => _saveProgress(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(onPressed: _addBookmark, icon: const Icon(CupertinoIcons.bookmark)),
            if (_pages > 0)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text('${_page + 1}/$_pages', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
        body: _error != null
            ? _ReaderError(title: widget.book.title, error: _error!)
            : PDFView(
                filePath: widget.book.path,
                enableSwipe: true,
                swipeHorizontal: true,
                pageFling: true,
                autoSpacing: false,
                defaultPage: math.max(0, _page),
                fitPolicy: FitPolicy.BOTH,
                onRender: (pages) {
                  setState(() => _pages = pages ?? 0);
                  _saveProgress();
                },
                onViewCreated: (controller) => _controller = controller,
                onPageChanged: (page, total) {
                  setState(() {
                    _page = page ?? 0;
                    _pages = total ?? _pages;
                  });
                  _saveProgress();
                },
                onError: (error) => setState(() => _error = error.toString()),
                onPageError: (page, error) => setState(() => _error = 'Halaman $page: $error'),
              ),
        bottomNavigationBar: _pages <= 0
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text('${_page + 1}'),
                      Expanded(
                        child: Slider(
                          value: _page.toDouble().clamp(0, math.max(0, _pages - 1)).toDouble(),
                          min: 0,
                          max: math.max(0, _pages - 1).toDouble(),
                          onChanged: (v) async {
                            final target = v.round();
                            await _controller?.setPage(target);
                          },
                        ),
                      ),
                      Text('$_pages'),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.title, required this.error});
  final String title;
  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.exclamationmark_triangle, size: 42),
            const SizedBox(height: 12),
            Text('Gagal membuka $title', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

Future<String> _readPlainText(String path) async {
  final bytes = await File(path).readAsBytes();
  return utf8.decode(bytes, allowMalformed: true).replaceAll('\r\n', '\n');
}

Future<String> _readEpubText(String path) async {
  final bytes = await File(path).readAsBytes();
  final zip = archive.ZipDecoder().decodeBytes(bytes);
  final htmlFiles = zip.files.where((file) {
    final name = file.name.toLowerCase();
    return file.isFile && (name.endsWith('.xhtml') || name.endsWith('.html') || name.endsWith('.htm'));
  }).toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  final buffer = StringBuffer();
  for (final file in htmlFiles) {
    final data = file.readBytes();
    if (data == null) continue;
    final html = utf8.decode(data, allowMalformed: true);
    final text = _htmlToText(html);
    if (text.trim().isNotEmpty) {
      buffer.writeln(text.trim());
      buffer.writeln('\n');
    }
  }
  return buffer.toString().trim();
}

String _htmlToText(String html) {
  var text = html;
  text = text.replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), ' ');
  text = text.replaceAll(RegExp(r'</(p|div|h1|h2|h3|h4|h5|h6|li|section|article|br)>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  text = text.replaceAll(RegExp(r'\n\s+'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

List<String> _paginate(String text, ReaderSettings settings) {
  final cleaned = text.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (cleaned.isEmpty) return [];

  final fontFactor = 18 / settings.fontSize;
  final lineFactor = 1.55 / settings.lineHeight;
  final marginFactor = 24 / settings.margin.clamp(12, 44).toDouble();
  final target = (1120 * fontFactor * lineFactor * marginFactor).round().clamp(520, 1900).toInt();

  final paragraphs = cleaned.split(RegExp(r'\n\s*\n'));
  final pages = <String>[];
  final buffer = StringBuffer();

  void flush() {
    final page = buffer.toString().trim();
    if (page.isNotEmpty) pages.add(page);
    buffer.clear();
  }

  for (final raw in paragraphs) {
    final paragraph = raw.trim();
    if (paragraph.isEmpty) continue;

    if (paragraph.length > target) {
      final words = paragraph.split(RegExp(r'\s+'));
      for (final word in words) {
        if (buffer.length + word.length + 1 > target) flush();
        buffer.write(word);
        buffer.write(' ');
      }
      buffer.write('\n\n');
      continue;
    }

    if (buffer.length + paragraph.length + 2 > target) flush();
    buffer.writeln(paragraph);
    buffer.writeln();
  }
  flush();
  return pages;
}

Future<int> _estimateTotalUnits(String path, BookFormat format) async {
  try {
    if (format == BookFormat.txt) {
      final text = await _readPlainText(path);
      return math.max(1, (text.length / 1200).ceil());
    }
    if (format == BookFormat.epub) {
      final text = await _readEpubText(path);
      return math.max(1, (text.length / 1200).ceil());
    }
    if (format == BookFormat.cbz) {
      final bytes = await File(path).readAsBytes();
      final zip = archive.ZipDecoder().decodeBytes(bytes);
      return zip.files.where((f) {
        final n = f.name.toLowerCase();
        return f.isFile && (n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') || n.endsWith('.webp'));
      }).length;
    }
  } catch (_) {}
  return 0;
}

int _progressToPage(double progress, int total) {
  if (total <= 0) return 0;
  return ((progress.clamp(0.0, 1.0).toDouble() * total).floor()).clamp(0, math.max(0, total - 1)).toInt();
}

BookFormat _formatFromPath(String path) {
  final ext = p.extension(path).toLowerCase();
  if (ext == '.pdf') return BookFormat.pdf;
  if (ext == '.epub') return BookFormat.epub;
  if (ext == '.txt') return BookFormat.txt;
  if (ext == '.cbz' || ext == '.zip') return BookFormat.cbz;
  return BookFormat.unknown;
}

String _titleFromFile(String fileName) {
  final base = p.basenameWithoutExtension(fileName).replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  if (base.isEmpty) return 'Tanpa Judul';
  return base.split(RegExp(r'\s+')).map((word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + (word.length > 1 ? word.substring(1) : '');
  }).join(' ');
}

String _safeFileName(String input) {
  final cleaned = input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  return cleaned.isEmpty ? 'book.file' : cleaned;
}

String _initials(String title) {
  final words = title.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (words.isEmpty) return 'BR';
  String firstChar(String value) => String.fromCharCode(value.runes.first);
  if (words.length == 1) {
    final chars = words.first.runes.take(2).map(String.fromCharCode).join();
    return chars.toUpperCase();
  }
  return '${firstChar(words[0])}${firstChar(words[1])}'.toUpperCase();
}

const List<Color> _coverColors = [
  Color(0xFF6C63FF),
  Color(0xFF00A896),
  Color(0xFFFF7A59),
  Color(0xFF2D9CDB),
  Color(0xFFB83280),
  Color(0xFF111827),
  Color(0xFF8B5CF6),
  Color(0xFF0EA5E9),
];

extension FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}
