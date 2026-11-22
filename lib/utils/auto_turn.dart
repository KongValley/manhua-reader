import 'dart:async';

/// Schedules automatic page turns without depending on the reader widget.
/// 独立于阅读器组件的自动翻页计时器。
class AutoTurnController {
  AutoTurnController({required this.onTurn, this.canTurn});

  /// Returns true when a page was turned and another timer should be scheduled.
  /// 返回 true 表示已翻页，可以继续安排下一次。
  final bool Function() onTurn;

  /// Optional guard, such as a modal route being open.
  /// 可选守卫，例如有弹层打开时暂停。
  final bool Function()? canTurn;

  Duration? _interval;
  Timer? _timer;
  bool _active = true;

  bool get isRunning => _timer != null;

  void configure(Duration? interval) {
    _interval = interval;
    _restart();
  }

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (active) {
      _restart();
    } else {
      _cancel();
    }
  }

  void restart() => _restart();

  void dispose() => _cancel();

  void _restart() {
    _cancel();
    final interval = _interval;
    if (!_active || interval == null || interval <= Duration.zero) return;
    _timer = Timer(interval, _tick);
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    _timer = null;
    if (!_active) return;
    if (canTurn != null && !canTurn!()) {
      _restart();
      return;
    }
    if (onTurn()) _restart();
  }
}
