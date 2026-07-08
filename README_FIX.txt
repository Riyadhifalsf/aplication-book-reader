Babeh Reader v5 Stable Android

Perubahan:
- pdfrx dihapus, jadi log asset web pdfium.wasm/pdfium_client.js/pdfium_worker.js tidak muncul lagi.
- file_picker tetap tidak dipakai. Import file pakai file_selector.
- PDF diganti ke flutter_pdfview untuk Android/iOS.
- Navigasi bawah dihapus. Semua menu dipindah ke hamburger drawer.
- Mode baca halaman digeser seperti buku dijadikan default.
- TXT/EPUB dibaca dengan PageView.
- CBZ dibaca per gambar dengan PageView.
- Online catalog dan download offline tetap ada.

Cara pasang:
1. Extract ZIP ini.
2. Copy pubspec.yaml dan folder lib/ ke project babeh_reader kamu.
3. Jalankan:
   rm -f pubspec.lock
   flutter clean
   flutter pub get
   flutter run -d PNBUOFTCEA4HA6JR

Catatan:
- Format stabil: PDF, EPUB sederhana, TXT, CBZ.
- CBR/DOC/DOCX/MOBI/DJVU/CHM masih ditampilkan statusnya, tapi belum reader internal.
