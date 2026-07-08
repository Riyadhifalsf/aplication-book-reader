# Babeh Reader v6 Offline Modern

Versi ini dibuat full offline. Tidak ada katalog online, tidak ada HTTP, dan tidak ada pdfrx/web asset.

## Replace file
Copy ke project Flutter kamu:

- `pubspec.yaml`
- `lib/main.dart`

Lalu jalankan:

```bash
rm -f pubspec.lock
flutter clean
flutter pub get
flutter run -d PNBUOFTCEA4HA6JR
```

## Penting
Kalau sebelumnya kamu pernah menambahkan izin internet di `android/app/src/main/AndroidManifest.xml`, hapus baris ini agar aplikasinya benar-benar offline-only:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

## Format stabil
- PDF: dibuka offline pakai `flutter_pdfview`
- TXT: dibaca offline dengan halaman geser
- EPUB: parser sederhana offline dari isi XHTML/HTML di dalam file EPUB
- CBZ/ZIP komik: gambar dibaca offline dari ZIP/CBZ

CBR, MOBI, DJVU, DOCX belum dibuat reader native karena butuh parser tambahan yang lebih berat.


## v6.1 compile fix
- Ganti ikon CupertinoIcons.books_vertical ke CupertinoIcons.book.
- Ubah avg progress menjadi double agar cocok dengan _TinyProgress.
