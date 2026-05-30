import 'package:flutter/widgets.dart';

/// Returns a valid, non-zero `sharePositionOrigin` rect for share_plus.
///
/// iOS anchors the share sheet (UIActivityViewController) to a source rect.
/// share_plus forwards `sharePositionOrigin`; when it is null or a zero rect,
/// iOS throws:
///   PlatformException(sharePositionOrigin: argument must be set,
///   {{0, 0}, {0, 0}} must be non-zero and within coordinate space of source
///   view)
/// — exactly what crashed the profile / invite / export share buttons.
///
/// The rect is derived from the render box of [context] (usually the share
/// button), so on iPad the popover points at the tapped control. If the box is
/// not laid out yet we fall back to a 1×1 rect at the screen centre — still a
/// valid non-zero rect, so the share call never crashes.
Rect shareOrigin(BuildContext context) {
  final object = context.findRenderObject();
  if (object is RenderBox &&
      object.hasSize &&
      object.size.width > 0 &&
      object.size.height > 0) {
    return object.localToGlobal(Offset.zero) & object.size;
  }
  final size = MediaQuery.maybeOf(context)?.size ?? const Size(400, 800);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: 1,
    height: 1,
  );
}
