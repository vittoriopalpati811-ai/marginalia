class ImportResult {
  const ImportResult({
    required this.booksAdded,
    required this.highlightsAdded,
    required this.highlightsDeduplicated,
  });

  final int booksAdded;
  final int highlightsAdded;
  final int highlightsDeduplicated;
}

class ImportService {
  const ImportService(dynamic isar, String userId);

  Future<ImportResult> importClippingsText(String rawText) async {
    return const ImportResult(
      booksAdded: 0,
      highlightsAdded: 0,
      highlightsDeduplicated: 0,
    );
  }
}
