import 'package:flutter/material.dart';

/// A több képernyőn közös háttérkép (Nagyvázsony látkép). A `cacheWidth`
/// a képernyő fizikai szélességéhez igazítja a dekódolt bitmapet, így a
/// teljes felbontású kép nem terheli feleslegesen a memóriát/CPU-t — ez a
/// korábbi, cacheWidth nélküli teljes dekódolás okozta akadozás fő forrása.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, this.alignment = Alignment.center});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final decodeWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return Image.asset(
      'assets/var.jpg',
      fit: BoxFit.cover,
      alignment: alignment,
      cacheWidth: decodeWidth,
    );
  }
}
