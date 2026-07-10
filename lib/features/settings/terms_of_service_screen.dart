import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import 'legal_doc_web_view.dart';

/// In-app Terms of Service (EULA). Delegates to [LegalDocWebView], which renders
/// the bundled HTML (IT/EN by [isItalian]) inside a WebView so the terms live
/// *inside* the app instead of opening an external GitHub link — an App Store
/// expectation (Guideline 1.2, user-generated content requires an agreed-to
/// EULA). Falls back to an "open in browser" button where webview_flutter isn't
/// supported (e.g. the Windows dev build) so it never crashes there.
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key, required this.isItalian});

  final bool isItalian;

  @override
  Widget build(BuildContext context) {
    return LegalDocWebView(
      title: context.l10n.termsTitle,
      isItalian: isItalian,
      itAssetPath: 'docs/terms/it/index.html',
      enAssetPath: 'docs/terms/index.html',
      itUrl: 'https://get-scripta.app/terms/it/',
      enUrl: 'https://get-scripta.app/terms/',
    );
  }
}
