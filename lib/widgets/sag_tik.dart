import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kod_yardimci.dart';

/// 1.30.3: telefonda basılı tutunca açılan menü, bilgisayar tarayıcısında
/// (Edge / Chrome / Firefox) sağ tıkla da açılır. Fare satırın üstündeyken
/// tarayıcının kendi sağ tık menüsü kapatılır, çıkınca geri açılır.
/// Telefonda ve iPhone Safari'de hiçbir şey değişmez (basılı tutmak yeter).
class SagTik extends StatefulWidget {
  const SagTik({super.key, required this.onMenu, required this.child});

  final VoidCallback? onMenu;
  final Widget child;

  @override
  State<SagTik> createState() => _SagTikState();
}

class _SagTikState extends State<SagTik> {
  bool _kapali = false;

  void _tarayiciMenusu(bool ac) {
    if (_kapali == !ac) return;
    _kapali = !ac;
    unawaited((ac
            ? BrowserContextMenu.enableContextMenu()
            : BrowserContextMenu.disableContextMenu())
        .catchError((_) {}));
  }

  @override
  void dispose() {
    if (_kapali) _tarayiciMenusu(true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!bilgisayarTarayicisi || widget.onMenu == null) return widget.child;
    return MouseRegion(
      onEnter: (_) => _tarayiciMenusu(false),
      onExit: (_) => _tarayiciMenusu(true),
      child: GestureDetector(
        onSecondaryTap: widget.onMenu,
        child: widget.child,
      ),
    );
  }
}

/// Bilgisayar tarayıcısında satırın sonunda görünen ⋮ (seçenekler) düğmesi;
/// telefonda görünmez (orada basılı tutulur).
class MenuDugmesi extends StatelessWidget {
  const MenuDugmesi({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!bilgisayarTarayicisi || onPressed == null) {
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Seçenekler (sağ tık)',
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}
