import 'package:flutter/cupertino.dart';
import 'vault_motion.dart';

class VaultPageRoute<T> extends CupertinoPageRoute<T> {
  VaultPageRoute({
    required super.builder,
    super.title,
    super.settings,
    super.maintainState = true,
    super.fullscreenDialog = false,
  });

  @override
  Duration get transitionDuration => VaultMotion.pageTransitionDuration;
}
