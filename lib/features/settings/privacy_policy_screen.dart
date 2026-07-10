import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import 'legal_doc_web_view.dart';

/// In-app privacy policy. Delegates to [LegalDocWebView], which renders the
/// bundled HTML (IT/EN by [isItalian]) inside a WebView so the policy lives
/// *inside* the app instead of opening an external GitHub link — an App Store
/// expectation and what the founder asked for. Falls back to an "open in
/// browser" button where webview_flutter isn't supported (e.g. the Windows dev
/// build) so it never crashes there.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key, required this.isItalian});

  final bool isItalian;

  @override
  Widget build(BuildContext context) {
    return LegalDocWebView(
      title: context.l10n.privacyTitle,
      isItalian: isItalian,
      itAssetPath: 'docs/privacy/it/index.html',
      enAssetPath: 'docs/privacy/index.html',
      itUrl: 'https://get-scripta.app/privacy/it/',
      enUrl: 'https://get-scripta.app/privacy/',
    );
  }
}
