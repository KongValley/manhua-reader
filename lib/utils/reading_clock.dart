/// Measures active reading intervals using monotonic time.
/// 使用单调时钟累计有效阅读时间。
class ReadingClock {
  ReadingClock({Duration Function()? now}) : _now = now ?? _systemClock();

  final Duration Function() _now;
  Duration? _startedAt;
  Duration _unrecorded = Duration.zero;

  bool get isRunning => _startedAt != null;

  void start() => _startedAt ??= _now();

  void pause() {
    _checkpoint();
    _startedAt = null;
  }

  /// Returns whole seconds while carrying the fractional remainder forward.
  /// 返回已累计的整秒数，并保留不足一秒的余量。
  int takeSeconds() {
    _checkpoint();
    final seconds = _unrecorded.inSeconds;
    _unrecorded -= Duration(seconds: seconds);
    return seconds;
  }

  void _checkpoint() {
    final startedAt = _startedAt;
    if (startedAt == null) return;
    final now = _now();
    _unrecorded += now - startedAt;
    _startedAt = now;
  }

  static Duration Function() _systemClock() {
    final clock = Stopwatch()..start();
    return () => clock.elapsed;
  }
}
