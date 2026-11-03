import 'package:flutter/material.dart';

import '../../config/app_assets.dart';
import '../../config/slotbook_theme.dart';
import '../utils.dart';

/// The SlotBook "slot board" mark (a hanging board with booked slots cut out). Always use this widget instead of loading the image directly.
///
/// The asset is white art on transparency, so it is tinted at draw time ([BlendMode.srcIn]):
/// drawn raw, it would vanish on light backgrounds. Default colour is the theme's emerald text
/// shade (readable in dark and light mode); pass [color] for coloured tiles, e.g. `onAccent`
/// on the emerald→lime gradient.
class SlotBookLogo extends StatelessWidget {
  const SlotBookLogo({super.key, this.size = 24, this.color, this.semanticLabel = 'SlotBook logo'});

  final double size;
  final Color? color;

  /// null = decorative (when a visible "SlotBook" wordmark sits right next to it).
  final String? semanticLabel;

  static String get assetPath => Utils.getImagePath(AppAssets.images.logo);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.extension<SlotBookColors>()?.cricketText ?? theme.colorScheme.primary;
    // Decode at the size actually shown: the full 1024px asset would cost ~4 MB of memory per size.
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      cacheWidth: decodeSize,
      cacheHeight: decodeSize,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium, // smooth edges when the 1024px mark is drawn small
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
