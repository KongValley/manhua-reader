import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../formats/comic_page_crop.dart';
import '../formats/comic_source.dart';
import '../formats/comic_source_factory.dart';
import '../models/comic_book.dart';
import '../models/reader_settings.dart';
import '../models/toc_entry.dart';
import '../services/library_repository.dart';
import '../services/pdf_password_flow.dart';
import '../services/screen_awake.dart';
import '../services/volume_keys.dart';
import '../theme/app_theme.dart';
import '../utils/auto_turn.dart';
import '../utils/format.dart';
import '../utils/pagination.dart';
import '../utils/reading_clock.dart';
import '../widgets/book_cover.dart';
import '../widgets/bookmark_editor_dialog.dart';
import '../widgets/comic_page_image.dart';
import '../widgets/paper_page_view.dart';
import '../widgets/pdf_password_dialog.dart';
import '../widgets/reader_navigation_sheet.dart';
import '../widgets/reader_settings_sheet.dart';
import '../widgets/reading_stats_sheet.dart';
import '../widgets/slider_ticks.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    required this.book,
    required this.repository,
    this.initialPage,
    super.key,
  });

  final ComicBook book;
  final LibraryRepository repository;
  final int? initialPage;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  static const double _pageGap = 6;

  ComicSource? _source;
  ComicPageCropController? _cropController;
  ComicPageLayoutSource? _layoutSource;
  Object? _openError;
  bool _loading = true;

  /// The book being read. Changes when the reader moves on to the next volume.
  /// 正在阅读的书；读到下一卷时会切换。
  late ComicBook _book;
  late ReadingMode _mode;
  late bool _rightToLeft;
  late bool _doublePage;
  late int _spreadOffset;
  late TapZoneWidth _tapZoneWidth;
  late bool _autoCrop;
  int _pageCount = 0;
  int _currentPage = 0;
  List<List<int>> _spreads = const [];
  Future<List<TocEntry>>? _tocFuture;
  List<TocEntry> _toc = const [];

  /// Next volume of the series, offered on the last page.
  /// 系列的下一卷，在最后一页提供入口。
  ComicBook? _nextVolume;

  /// Disables touch page turning for this reading session only.
  /// 仅在本次阅读内停用触摸翻页。
  bool _locked = false;

  /// Whether vertical scrolling has reached the end of the last page.
  /// 纵向滚动是否已到达最后一页的末尾。
  bool _verticalAtEnd = false;
  Timer? _readingTimeTimer;
  final _readingClock = ReadingClock();
  bool _routeVisible = true;

  PageController? _pageController;
  int? _pendingHorizontalPage;
  ScrollController? _verticalController;
  double _verticalWidth = -1;
  double _verticalHeight = -1;
  bool _verticalLayoutDirty = false;
  bool _verticalNeedsAnchor = false;
  int? _verticalAnimatingTargetPage;
  bool _restoringVerticalPosition = false;
  List<double> _pageOffsets = const [];
  ScaffoldMessengerState? _messenger;

  bool _chromeVisible = true;
  bool _sliderActive = false;
  Timer? _hideTimer;
  Timer? _persistTimer;
  late final AutoTurnController _autoTurn;
  late bool _keepAwake;
  late double _brightness;
  late double _warmth;
  late int _autoTurnSeconds;
  late bool _volumeKeys;
  late PageTurnAnimation _pageTurnAnimation;
  bool _appActive = true;

  LibraryRepository get _repository => widget.repository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _prepareForBook(widget.book);
    if (widget.initialPage != null) _currentPage = widget.initialPage!;
    _autoCrop = _repository.settings.autoCrop;
    _keepAwake = _repository.settings.keepAwake;
    _brightness = _repository.settings.brightness;
    _warmth = _repository.settings.warmth;
    _autoTurnSeconds = _repository.settings.autoTurnSeconds;
    _volumeKeys = _repository.settings.volumeKeys;
    _pageTurnAnimation = _repository.settings.pageTurnAnimation;
    _autoTurn = AutoTurnController(
      onTurn: _autoTurnPage,
      canTurn: _canAutoTurn,
    );
    _enterImmersiveMode();
    _applyKeepAwake();
    VolumeKeys.listen(onNext: _volumeNextPage, onPrevious: _volumePreviousPage);
    _applyVolumeKeys();
    _loadSource();
  }

  /// Adopts [book] together with its own reading preferences, falling back
  /// to the global defaults for anything the book has not remembered.
  /// 切换到 [book] 并载入它自己的阅读偏好，没有单独记录的项目跟随全局设置。
  void _prepareForBook(ComicBook book) {
    final settings = _repository.settings;
    _book = book;
    _mode = book.readingMode ?? settings.mode;
    _rightToLeft = book.rightToLeft ?? settings.rightToLeft;
    _doublePage = book.doublePage ?? settings.doublePage;
    _spreadOffset = book.spreadOffset ?? settings.spreadOffset;
    _tapZoneWidth = settings.tapZoneWidth;
    _currentPage = book.safeLastPage;
  }

  Future<void> _loadSource() async {
    final book = _book;
    try {
      final passwords = PdfPasswordFlow(
        book: book,
        prompt: (errorText) async {
          if (!mounted || book != _book) return null;
          return showPdfPasswordDialog(
            context,
            fileName: book.title,
            errorText: errorText,
          );
        },
      );
      final source = await ComicSourceFactory.open(
        book,
        passwordProvider: passwords.provide,
      );
      // The reader moved on to another volume while this one was opening.
      // 打开过程中阅读器已切换到另一卷。
      if (!mounted || book != _book) {
        await source.dispose();
        return;
      }
      unawaited(
        passwords.onSuccess(book).then((saved) {
          if (!saved && mounted && book == _book) {
            _showReaderNotice('无法记住密码，本次仍可阅读');
          }
        }),
      );
      final pageCount = source.pageCount;
      if (book.pageCount != pageCount) {
        book.pageCount = pageCount;
        book.lastPage = clampPage(book.lastPage, pageCount);
        book.bookmarks.removeWhere(
          (bookmark) => bookmark.page < 0 || bookmark.page >= pageCount,
        );
      }
      final initialPage = clampPage(_currentPage, pageCount);
      final layoutSource = source is ComicPageLayoutSource
          ? source as ComicPageLayoutSource
          : null;
      _bindLayoutSource(layoutSource);
      if (layoutSource != null) {
        try {
          await layoutSource.ensurePageSizes([initialPage]);
        } catch (_) {
          // Size discovery is best effort; rendering reports page errors.
          // 尺寸探测是尽力而为，页面错误留到渲染时报告。
        }
        if (!mounted || book != _book) {
          _unbindLayoutSource();
          await source.dispose();
          return;
        }
      }
      final crop = ComicPageCropController(source)..addListener(_onCropChanged);
      setState(() {
        _source = source;
        _cropController = crop;
        _pageCount = pageCount;
        _currentPage = initialPage;
        _spreads = buildSpreads(pageCount, offset: _spreadOffset);
        _tocFuture = source.loadToc();
        _pageController = _startingPageController();
        _loading = false;
      });
      _nextVolume = _repository.nextVolumeInSeries(book);
      unawaited(_adoptToc(_tocFuture!));
      _persistProgressNow();
      _syncReadingTimer();
      _applyVolumeKeys();
      _scheduleAutoTurn();
      _scheduleChromeHide();
    } catch (error) {
      if (!mounted || book != _book) return;
      setState(() {
        _openError = error;
        _loading = false;
      });
    }
  }

  Future<void> _adoptToc(Future<List<TocEntry>> future) async {
    final toc = await future.catchError((Object _) => const <TocEntry>[]);
    if (!mounted || future != _tocFuture) return;
    setState(() => _toc = toc);
  }

  void _bindLayoutSource(ComicPageLayoutSource? source) {
    if (identical(source, _layoutSource)) return;
    _layoutSource?.pageSizesChanged.removeListener(_onPageSizesChanged);
    _layoutSource = source;
    _layoutSource?.pageSizesChanged.addListener(_onPageSizesChanged);
  }

  void _unbindLayoutSource() {
    _layoutSource?.pageSizesChanged.removeListener(_onPageSizesChanged);
    _layoutSource = null;
  }

  void _onPageSizesChanged() {
    if (!mounted || _source == null) return;
    _verticalLayoutDirty = true;
    setState(() {});
  }

  void _ensurePageSizesAround(int page) {
    final source = _layoutSource;
    if (source == null) return;
    unawaited(
      source
          .ensurePageSizes({page - 1, page, page + 1})
          .catchError((Object _) {}),
    );
  }

  /// Replaces the current volume with [next] without leaving the reader, so
  /// system UI, keep-awake and key handling stay in place.
  /// 在阅读器内直接切换到 [next]，系统栏、常亮和按键处理保持不变。
  Future<void> _switchToBook(ComicBook next) async {
    if (next == _book || _loading) return;
    if (!_repository.fileExists(next)) {
      _showReaderNotice('下一卷文件不可用，可在书架中重新定位');
      return;
    }
    _hideTimer?.cancel();
    _persistTimer?.cancel();
    _persistTimer = null;
    _messenger?.hideCurrentSnackBar();
    _persistProgressNow();
    _stopReadingTimer();
    _autoTurn.configure(null);
    _unbindLayoutSource();
    final source = _source;
    final crop = _cropController;
    final pageController = _pageController;
    final verticalController = _verticalController;
    verticalController?.removeListener(_onVerticalScroll);
    setState(() {
      _source = null;
      _cropController = null;
      _openError = null;
      _loading = true;
      _tocFuture = null;
      _toc = const [];
      _nextVolume = null;
      _spreads = const [];
      _pageCount = 0;
      _verticalAtEnd = false;
      _pageController = null;
      _verticalController = null;
      _verticalWidth = -1;
      _pageOffsets = const [];
      _pendingHorizontalPage = null;
      _prepareForBook(next);
    });
    crop?.dispose();
    _applyVolumeKeys();
    _disposeLater(pageController);
    _disposeLater(verticalController);
    if (source != null) {
      // Let the page widgets finish tearing down before releasing PDFium.
      // 先让页面组件完成卸载，再释放 PDFium。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(source.dispose());
      });
    }
    _keepChromeVisible();
    await _loadSource();
  }

  bool get _onLastPage =>
      _pageCount > 0 && _visibleSpread.last >= _pageCount - 1;

  /// Offers the next volume once the last page is reached.
  /// 读到最后一页时提示可以继续下一卷。
  void _announceLastPage() {
    if (_nextVolume != null && _onLastPage) _keepChromeVisible();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
    // Subscribe to route coverage, including reader menus and dialogs.
    // 跟踪路由是否被阅读菜单或对话框覆盖。
    _routeVisible = ModalRoute.isCurrentOf(context) ?? true;
    _syncReadingTimer();
    _applyVolumeKeys();
  }

  void _syncReadingTimer() {
    if (_source == null || _loading || !_appActive || !_routeVisible) {
      _stopReadingTimer();
      return;
    }
    if (_readingClock.isRunning) return;
    _readingClock.start();
    _readingTimeTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _flushReadingTime(),
    );
  }

  void _flushReadingTime({bool notify = true}) => _repository.addReadingTime(
    _readingClock.takeSeconds(),
    book: _book,
    notify: notify,
  );

  void _stopReadingTimer({bool notify = true}) {
    _readingTimeTimer?.cancel();
    _readingTimeTimer = null;
    _readingClock.pause();
    _flushReadingTime(notify: notify);
  }

  void _retryOpen() {
    setState(() {
      _loading = true;
      _openError = null;
    });
    _loadSource();
  }

  bool get _usesSpreads => _doublePage && _mode == ReadingMode.horizontal;

  int _slotForPage(int page) =>
      _usesSpreads ? spreadIndexForPage(_spreads, page) : page;

  PageController _startingPageController() =>
      PageController(initialPage: _slotForPage(_currentPage), keepPage: false);

  List<int> get _visibleSpread {
    if (_usesSpreads && _spreads.isNotEmpty) {
      return _spreads[spreadIndexForPage(_spreads, _currentPage)];
    }
    return [_currentPage];
  }

  String get _pageNumberText {
    if (_pageCount <= 0) return '0';
    final spread = _visibleSpread;
    if (spread.length > 1) {
      return '${spread.first + 1}–${spread.last + 1}';
    }
    return '${spread.first + 1}';
  }

  String get _pageCounterText => '$_pageNumberText / $_pageCount';

  String get _pageSubtitleText => '第 $_pageNumberText / $_pageCount 页';

  /// Title of the chapter containing the current page, or '' when the file
  /// has no chapter information.
  /// 当前页所在章节的标题；文件没有章节信息时返回空字符串。
  String get _chapterTitle {
    TocEntry? current;
    for (final entry in _toc) {
      if (entry.page <= _currentPage &&
          (current == null || entry.page >= current.page)) {
        current = entry;
      }
    }
    return current?.title ?? '';
  }

  String get _topSubtitleText {
    final chapter = _chapterTitle;
    return chapter.isEmpty
        ? '${_book.format.label} · $_pageSubtitleText'
        : '$_pageSubtitleText · $chapter';
  }

  Widget _buildNextVolumeCard() {
    final next = _nextVolume;
    final visible =
        _chromeVisible &&
        next != null &&
        (_mode == ReadingMode.horizontal ? _onLastPage : _verticalAtEnd);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      left: 24,
      right: 24,
      // Sits just above the bottom bar while the menu is visible.
      // 菜单显示时停在底部工具栏上方。
      bottom: safeBottom + (_chromeVisible ? 136 : 18),
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
              child: child,
            ),
          ),
          // Keep the card out of the tree while it has nothing to offer.
          // 没有可读的下一卷时不构建卡片。
          child: !visible
              ? const SizedBox.shrink()
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _NextVolumeCard(
                      title: next.title,
                      onTap: () => _switchToBook(next),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  void _enterImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active == _appActive) return;
    _appActive = active;
    _syncReadingTimer();
    _autoTurn.setActive(active);
    _applyKeepAwake();
    _applyVolumeKeys();
    if (active) {
      _enterImmersiveMode();
      _scheduleAutoTurn();
    } else {
      _persistProgressNow();
      unawaited(_repository.flush());
    }
  }

  void _applyKeepAwake() {
    unawaited(ScreenAwake.setEnabled(_appActive && _keepAwake));
  }

  void _applyVolumeKeys() {
    unawaited(
      VolumeKeys.setEnabled(
        _volumeKeys && _canAutoTurn() && VolumeKeys.isSupported,
      ),
    );
  }

  void _volumeNextPage() {
    if (!_appActive || !_canAutoTurn() || _pageCount <= 0) return;
    _goNext(revealChrome: true);
  }

  void _volumePreviousPage() {
    if (!_appActive || !_canAutoTurn() || _pageCount <= 0) return;
    _goPrevious(revealChrome: true);
  }

  /// Schedules a single automatic page turn after the configured delay.
  /// 按设定间隔安排下一次自动翻页。
  void _scheduleAutoTurn() {
    _autoTurn.configure(
      _autoTurnSeconds <= 0 || _pageCount <= 1
          ? null
          : Duration(seconds: _autoTurnSeconds),
    );
  }

  bool _canAutoTurn() =>
      !_loading && _source != null && _appActive && _routeVisible && !_sliderActive;

  bool _autoTurnPage() {
    if (!mounted || !_canAutoTurn() || _pageCount <= 1) return false;
    if (_mode == ReadingMode.vertical ? _verticalAtEnd : _onLastPage) {
      _showReaderNotice('已到最后一页，自动翻页已停止');
      return false;
    }
    if (_mode == ReadingMode.vertical) {
      _scrollVertical(1);
    } else {
      _goNext();
    }
    return true;
  }

  void _scheduleChromeHide() {
    _hideTimer?.cancel();
    if (!_chromeVisible || _sliderActive) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _sliderActive) return;
      setState(() => _chromeVisible = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) {
      _scheduleChromeHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _keepChromeVisible() {
    if (!_chromeVisible) {
      setState(() => _chromeVisible = true);
    }
    _scheduleChromeHide();
  }

  void _handlePageChanged(int page) {
    if (page == _currentPage) return;
    _ensurePageSizesAround(page);
    setState(() => _currentPage = page);
    _persistProgressSoon();
    _scheduleChromeHide();
    _scheduleAutoTurn();
    _announceLastPage();
  }

  void _handleSpreadChanged(int index) {
    if (index < 0 || index >= _spreads.length) return;
    final spread = _spreads[index];
    if (spread.contains(_currentPage)) return;
    _ensurePageSizesAround(spread.first);
    setState(() => _currentPage = spread.first);
    _persistProgressSoon();
    _scheduleChromeHide();
    _scheduleAutoTurn();
    _announceLastPage();
  }

  void _persistProgressSoon() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 350), () {
      _persistTimer = null;
      if (mounted) _persistProgressNow();
    });
  }

  void _persistProgressNow({bool notify = true}) {
    if (_source == null || _loading || _pageCount == 0) return;
    final finished = _mode == ReadingMode.vertical
        ? _verticalAtEnd
        : _onLastPage;
    _repository.updateProgress(
      _book,
      finished ? _pageCount - 1 : _currentPage,
      notify: notify,
    );
  }

  void _handleHorizontalSettled(int slot) {
    final requested = _pendingHorizontalPage;
    _pendingHorizontalPage = null;
    if (requested != null && _slotForPage(requested) == slot) {
      _handlePageChanged(requested);
    } else if (_usesSpreads) {
      _handleSpreadChanged(slot);
    } else {
      _handlePageChanged(slot);
    }
  }

  void _goToPage(int page, {bool animate = true, bool revealChrome = false}) {
    if (_loading || _source == null || _pageCount <= 0) return;
    final target = clampPage(page, _pageCount);
    _ensurePageSizesAround(target);
    if (revealChrome) _keepChromeVisible();

    if (_mode == ReadingMode.horizontal) {
      final controller = _pageController;
      final targetSlot = _slotForPage(target);
      if (controller != null && controller.hasClients) {
        final distance = (targetSlot - _slotForPage(_currentPage)).abs();
        if (animate &&
            distance == 1 &&
            !MediaQuery.disableAnimationsOf(context)) {
          if (_pendingHorizontalPage != target) {
            _pendingHorizontalPage = target;
            unawaited(
              controller.animateToPage(
                targetSlot,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeInOutCubic,
              ),
            );
          }
          return;
        }
        _pendingHorizontalPage = null;
        _handlePageChanged(target);
        if (controller.page != targetSlot) controller.jumpToPage(targetSlot);
      } else if (target != _currentPage) {
        setState(() {
          _pendingHorizontalPage = null;
          _currentPage = target;
          _pageController = _startingPageController();
        });
        _disposeLater(controller);
        _persistProgressSoon();
      }
      return;
    }

    if (target != _currentPage) setState(() => _currentPage = target);
    _persistProgressSoon();
    _scheduleAutoTurn();
    final controller = _verticalController;
    if (controller == null ||
        !controller.hasClients ||
        target >= _pageOffsets.length) {
      return;
    }
    final offset = _pageOffsets[target].clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    if (animate) {
      _verticalAnimatingTargetPage = target;
      unawaited(
        controller
            .animateTo(
              offset,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
              if (_verticalAnimatingTargetPage == target) {
                _verticalAnimatingTargetPage = null;
              }
            }),
      );
    } else {
      _verticalAnimatingTargetPage = null;
      controller.jumpTo(offset);
    }
  }

  void _goPrevious({bool revealChrome = false}) {
    final activePage = _mode == ReadingMode.horizontal
        ? (_pendingHorizontalPage ?? _currentPage)
        : _currentPage;
    if (_usesSpreads && _spreads.isNotEmpty) {
      final index = spreadIndexForPage(_spreads, activePage);
      if (index > 0) {
        _goToPage(_spreads[index - 1].first, revealChrome: revealChrome);
      }
      return;
    }
    if (activePage > 0) {
      _goToPage(activePage - 1, revealChrome: revealChrome);
    }
  }

  void _goNext({bool revealChrome = false}) {
    final activePage = _mode == ReadingMode.horizontal
        ? (_pendingHorizontalPage ?? _currentPage)
        : _currentPage;
    if (_usesSpreads && _spreads.isNotEmpty) {
      final index = spreadIndexForPage(_spreads, activePage);
      if (index + 1 < _spreads.length) {
        _goToPage(_spreads[index + 1].first, revealChrome: revealChrome);
      }
      return;
    }
    if (activePage < _pageCount - 1) {
      _goToPage(activePage + 1, revealChrome: revealChrome);
    }
  }

  void _toggleMode() {
    _setMode(
      _mode == ReadingMode.horizontal
          ? ReadingMode.vertical
          : ReadingMode.horizontal,
    );
  }

  void _setMode(ReadingMode next) {
    if (next == _mode) return;
    _repository
      ..setReadingMode(next)
      ..setBookReadingMode(_book, next);
    _applyReadingLayout(mode: next);
  }

  void _toggleDirection() => _setRightToLeft(!_rightToLeft);

  void _setRightToLeft(bool value) {
    if (value == _rightToLeft) return;
    _repository
      ..setRightToLeft(value)
      ..setBookRightToLeft(_book, value);
    _applyReadingLayout(rightToLeft: value);
  }

  void _toggleDoublePage() {
    if (_pageCount <= 1) return;
    _setDoublePage(!_doublePage);
    if (!_doublePage) {
      _showReaderNotice('双页模式已关闭');
    } else if (MediaQuery.sizeOf(context).width < 600) {
      _showReaderNotice('双页模式已开启（横屏效果更好）');
    } else {
      _showReaderNotice('双页模式已开启');
    }
  }

  void _setDoublePage(bool value) {
    if (_pageCount <= 1 || value == _doublePage) return;
    _repository
      ..setDoublePage(value)
      ..setBookDoublePage(_book, value);
    _applyReadingLayout(doublePage: value);
  }

  void _setSpreadOffset(int offset) {
    if (offset == _spreadOffset) return;
    _repository
      ..setSpreadOffset(offset)
      ..setSpreadOffset(offset, book: _book);
    _applyReadingLayout(spreadOffset: offset);
  }

  /// Applies the effective preferences without changing global defaults.
  /// 应用生效的阅读偏好，不修改全局默认值。
  void _applyReadingLayout({
    ReadingMode? mode,
    bool? rightToLeft,
    bool? doublePage,
    int? spreadOffset,
  }) {
    final nextMode = mode ?? _mode;
    final nextDirection = rightToLeft ?? _rightToLeft;
    final nextDouble = doublePage ?? _doublePage;
    final nextOffset = spreadOffset ?? _spreadOffset;
    final modeChanged = nextMode != _mode;
    final rebuildHorizontal =
        nextMode == ReadingMode.horizontal &&
        (modeChanged ||
            nextDirection != _rightToLeft ||
            nextDouble != _doublePage ||
            (nextDouble && nextOffset != _spreadOffset));
    final oldPage = _pageController;
    final oldVertical = _verticalController;
    if (modeChanged) oldVertical?.removeListener(_onVerticalScroll);
    setState(() {
      _mode = nextMode;
      _rightToLeft = nextDirection;
      _doublePage = nextDouble;
      if (nextOffset != _spreadOffset) {
        _spreadOffset = nextOffset;
        _spreads = buildSpreads(_pageCount, offset: nextOffset);
      }
      if (modeChanged) {
        _verticalController = null;
        _verticalWidth = -1;
        _pageOffsets = const [];
        _verticalAtEnd = false;
      }
      if (modeChanged || rebuildHorizontal) {
        _pendingHorizontalPage = null;
        _pageController = nextMode == ReadingMode.horizontal
            ? _startingPageController()
            : null;
      }
    });
    if (oldPage != _pageController) _disposeLater(oldPage);
    if (modeChanged) _disposeLater(oldVertical);
    _keepChromeVisible();
    _scheduleAutoTurn();
  }

  void _setTapZoneWidth(TapZoneWidth value) {
    setState(() => _tapZoneWidth = value);
    _repository.setTapZoneWidth(value);
  }

  ComicPageCropController? get _activeCrop =>
      _autoCrop ? _cropController : null;

  void _setAutoCrop(bool value) {
    setState(() {
      _autoCrop = value;
      _verticalLayoutDirty = true;
      _verticalNeedsAnchor = true;
    });
    _repository.setAutoCrop(value);
  }

  void _onCropChanged() {
    if (!mounted || !_autoCrop || _mode != ReadingMode.vertical) return;
    setState(() => _verticalLayoutDirty = true);
  }

  ReaderLayoutPreferences _resetBookReadingPrefs() {
    final settings = _repository.settings;
    _repository.clearBookReadingPrefs(_book);
    _applyReadingLayout(
      mode: settings.mode,
      rightToLeft: settings.rightToLeft,
      doublePage: settings.doublePage,
      spreadOffset: settings.spreadOffset,
    );
    return (
      mode: _mode,
      rightToLeft: _rightToLeft,
      doublePage: _doublePage,
      spreadOffset: _spreadOffset,
    );
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
    _keepChromeVisible();
    _showReaderNotice(_locked ? '已锁定触摸翻页，点按屏幕可呼出菜单' : '已解除触摸翻页锁定');
  }

  Future<void> _openReaderSettings() async {
    _keepChromeVisible();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReaderSettingsSheet(
        mode: _mode,
        rightToLeft: _rightToLeft,
        doublePage: _doublePage,
        spreadOffset: _spreadOffset,
        tapZoneWidth: _tapZoneWidth,
        autoCrop: _autoCrop,
        canDoublePage: _pageCount > 1,
        hasBookPrefs:
            _book.readingMode != null ||
            _book.rightToLeft != null ||
            _book.doublePage != null ||
            _book.spreadOffset != null,
        keepAwake: _keepAwake,
        brightness: _brightness,
        warmth: _warmth,
        autoTurnSeconds: _autoTurnSeconds,
        volumeKeys: _volumeKeys,
        pageTurnAnimation: _pageTurnAnimation,
        isAndroid: Theme.of(context).platform == TargetPlatform.android,
        onModeChanged: _setMode,
        onRightToLeftChanged: _setRightToLeft,
        onDoublePageChanged: _setDoublePage,
        onSpreadOffsetChanged: _setSpreadOffset,
        onTapZoneWidthChanged: _setTapZoneWidth,
        onAutoCropChanged: _setAutoCrop,
        onResetBookPrefs: _resetBookReadingPrefs,
        onKeepAwakeChanged: (value) {
          setState(() => _keepAwake = value);
          _repository.setKeepAwake(value);
          _applyKeepAwake();
        },
        onBrightnessChanged: (value) {
          setState(() => _brightness = value);
          _repository.setReaderBrightness(value);
        },
        onWarmthChanged: (value) {
          setState(() => _warmth = value);
          _repository.setReaderWarmth(value);
        },
        onAutoTurnChanged: (value) {
          setState(() => _autoTurnSeconds = value);
          _repository.setAutoTurnSeconds(value);
          _scheduleAutoTurn();
        },
        onVolumeKeysChanged: (value) {
          setState(() => _volumeKeys = value);
          _repository.setVolumeKeys(value);
          _applyVolumeKeys();
        },
        onPageTurnAnimationChanged: (value) {
          setState(() => _pageTurnAnimation = value);
          _repository.setPageTurnAnimation(value);
        },
      ),
    );
    if (!mounted) return;
    _keepChromeVisible();
    _scheduleAutoTurn();
  }

  void _toggleBookmark() {
    final targetBook = _book;
    final page = _currentPage;
    final wasBookmarked = targetBook.isBookmarked(page);
    _repository.toggleBookmark(targetBook, page);
    setState(() {});
    _keepChromeVisible();
    if (wasBookmarked) {
      _showReaderNotice('已移除书签');
    } else {
      _showReaderNotice(
        '已添加书签 · 第 ${page + 1} 页',
        action: SnackBarAction(
          label: '命名',
          onPressed: () => _editBookmark(page, book: targetBook),
        ),
      );
    }
  }

  Future<void> _editBookmark(int page, {ComicBook? book}) async {
    final targetBook = book ?? _book;
    if (!mounted || targetBook != _book) return;
    final existing = targetBook.bookmarkAt(page);
    final result = await showBookmarkEditorDialog(
      context,
      page: page,
      existing: existing,
    );
    if (!mounted || result == null || targetBook != _book) return;
    _repository.setBookmark(
      targetBook,
      page,
      label: result.label,
      note: result.note,
    );
    setState(() {});
    _keepChromeVisible();
  }

  void _showReaderNotice(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(milliseconds: action == null ? 1400 : 3200),
          action: action,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(70, 0, 70, 110),
        ),
      );
  }

  Future<void> _openReadingStats() async {
    _hideTimer?.cancel();
    _stopReadingTimer();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReadingStatsSheet(repository: _repository),
    );
    if (!mounted) return;
    _syncReadingTimer();
    _keepChromeVisible();
    _scheduleAutoTurn();
  }

  Future<void> _openNavigation() async {
    final source = _source;
    if (source == null) return;
    _hideTimer?.cancel();
    setState(() => _chromeVisible = true);
    final tocFuture = _tocFuture ??= source.loadToc();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (sheetContext) => ReaderNavigationSheet(
        source: source,
        book: _book,
        repository: _repository,
        tocFuture: tocFuture,
        currentPage: _currentPage,
        onJump: (page) {
          Navigator.of(sheetContext).pop();
          _goToPage(page, revealChrome: true);
        },
      ),
    );
    if (!mounted) return;
    setState(() {});
    _keepChromeVisible();
    _scheduleAutoTurn();
  }

  void _disposeLater(ScrollController? controller) {
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
  }

  void _ensureVerticalLayout(double width, double height) {
    final source = _source;
    if (width <= 0 || source == null) return;
    final old = _verticalController;
    if (!_verticalLayoutDirty &&
        width == _verticalWidth &&
        height == _verticalHeight &&
        old != null) {
      return;
    }
    final needsAnchor =
        old == null || width != _verticalWidth || _verticalNeedsAnchor;
    final page = _currentPage;
    var fraction = 0.0;
    if (old != null && old.hasClients && _pageOffsets.length > page + 1) {
      final start = _pageOffsets[page];
      final length = _pageOffsets[page + 1] - start;
      if (length > 0) {
        fraction = ((old.offset - start) / length).clamp(0.0, 1.0);
      }
    }

    final crop = _activeCrop;
    final offsets = List<double>.filled(_pageCount + 1, 0);
    for (var index = 0; index < _pageCount; index++) {
      final size = crop?.pageSize(index) ?? source.pageSize(index);
      offsets[index + 1] = offsets[index] + width / size.aspectRatio + _pageGap;
    }
    _verticalWidth = width;
    _verticalHeight = height;
    _verticalLayoutDirty = false;
    _verticalNeedsAnchor = false;
    _pageOffsets = offsets;
    final anchor =
        offsets[page] + fraction * (offsets[page + 1] - offsets[page]);
    final controller = old ?? ScrollController(initialScrollOffset: anchor);
    if (old == null) controller.addListener(_onVerticalScroll);
    _verticalController = controller;
    final restoreEnd = _verticalAtEnd;
    _restoringVerticalPosition = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _verticalController != controller ||
          _pageOffsets != offsets) {
        return;
      }
      _restoringVerticalPosition = false;
      if (!controller.hasClients || !controller.position.hasContentDimensions) {
        return;
      }
      final position = controller.position;
      final animatingPage = _verticalAnimatingTargetPage;
      if (animatingPage != null && animatingPage < offsets.length) {
        final target = offsets[animatingPage].clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((controller.offset - target).abs() > 0.5) {
          unawaited(
            controller
                .animateTo(
                  target,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                )
                .whenComplete(() {
                  if (_verticalAnimatingTargetPage == animatingPage) {
                    _verticalAnimatingTargetPage = null;
                  }
                }),
          );
        }
        return;
      }
      if (!needsAnchor && position.isScrollingNotifier.value) {
        // Keep active touch drags or fling momentum intact while off-screen
        // page sizes settle.
        // 后台发现页面尺寸时，不打断用户正在进行的拖动或惯性滚动。
        _onVerticalScroll();
        return;
      }
      final target = restoreEnd
          ? position.maxScrollExtent
          : anchor.clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((controller.offset - target).abs() > 0.5) controller.jumpTo(target);
      _onVerticalScroll();
    });
  }

  void _onVerticalScroll() {
    final controller = _verticalController;
    if (_restoringVerticalPosition ||
        controller == null ||
        !controller.hasClients ||
        _pageOffsets.isEmpty) {
      return;
    }
    final position = controller.position;
    if (!position.hasContentDimensions) return;
    final offset = controller.offset;
    final atEnd = position.maxScrollExtent - offset < 2;
    var page = 0;
    var low = 0;
    var high = _pageCount - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_pageOffsets[mid] <= offset + 1) {
        page = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (atEnd) page = _pageCount - 1;
    if (page != _currentPage || atEnd != _verticalAtEnd) {
      final reachedEnd = atEnd && !_verticalAtEnd;
      setState(() {
        _currentPage = page;
        _verticalAtEnd = atEnd;
      });
      _ensurePageSizesAround(page);
      _persistProgressSoon();
      if (reachedEnd) _announceLastPage();
    }
  }

  /// Scrolls the vertical reader by most of one screen in [direction].
  /// 在纵向阅读时滚动接近一屏的距离，[direction] 为 1 向下、-1 向上。
  void _scrollVertical(int direction) {
    final controller = _verticalController;
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    final step = position.viewportDimension * 0.9;
    final target = (position.pixels + direction * step)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() < 0.5) return;
    _scheduleAutoTurn();
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// Keyboard step forward: a page turn, or one screen in vertical mode.
  /// 键盘前进一步：翻一页，纵向模式下滚动一屏。
  void _stepForward() => _mode == ReadingMode.vertical
      ? _scrollVertical(1)
      : _goNext(revealChrome: true);

  void _stepBackward() => _mode == ReadingMode.vertical
      ? _scrollVertical(-1)
      : _goPrevious(revealChrome: true);

  void _goToEnd() {
    final controller = _verticalController;
    if (_mode == ReadingMode.vertical &&
        controller != null &&
        controller.hasClients) {
      _keepChromeVisible();
      controller.jumpTo(controller.position.maxScrollExtent);
      _onVerticalScroll();
    } else {
      _goToPage(_pageCount - 1, revealChrome: true);
    }
  }

  Future<void> _showJumpDialog() async {
    _hideTimer?.cancel();
    final result = await showDialog<int>(
      context: context,
      builder: (context) => _JumpPageDialog(
        currentPage: _currentPage,
        pageCount: _pageCount,
      ),
    );
    if (!mounted) return;
    if (result != null) {
      _goToPage(result - 1, revealChrome: true);
    }
    _scheduleChromeHide();
    _scheduleAutoTurn();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unbindLayoutSource();
    _hideTimer?.cancel();
    _persistTimer?.cancel();
    _stopReadingTimer(notify: false);
    _autoTurn.dispose();
    VolumeKeys.stop();
    unawaited(VolumeKeys.setEnabled(false));
    unawaited(ScreenAwake.setEnabled(false));
    _persistProgressNow(notify: false);
    unawaited(_repository.flush());
    final messenger = _messenger;
    if (messenger != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (messenger.mounted) {
          messenger.hideCurrentSnackBar();
        }
      });
    }
    _pageController?.dispose();
    _verticalController?.dispose();
    final source = _source;
    _source = null;
    _cropController?.dispose();
    if (source != null) {
      // Let the page widgets finish tearing down before releasing PDFium.
      // 先让页面组件完成卸载，再释放 PDFium。
      unawaited(
        Future<void>.delayed(
          Duration.zero,
          source.dispose,
        ).catchError((Object _) {}),
      );
    }
    _restoreSystemUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _LoadingView(title: _book.title);
    }
    if (_openError != null || _source == null) {
      return _ErrorView(
        title: _book.title,
        message: _openError?.toString() ?? '无法打开这本漫画',
        onRetry: _retryOpen,
      );
    }

    final source = _source!;
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _rightToLeft
          ? _goNext(revealChrome: true)
          : _goPrevious(revealChrome: true),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => _rightToLeft
          ? _goPrevious(revealChrome: true)
          : _goNext(revealChrome: true),
      const SingleActivator(LogicalKeyboardKey.arrowUp): _stepBackward,
      const SingleActivator(LogicalKeyboardKey.arrowDown): _stepForward,
      const SingleActivator(LogicalKeyboardKey.pageUp): _stepBackward,
      const SingleActivator(LogicalKeyboardKey.pageDown): _stepForward,
      const SingleActivator(LogicalKeyboardKey.home): () =>
          _goToPage(0, revealChrome: true),
      const SingleActivator(LogicalKeyboardKey.end): _goToEnd,
      const SingleActivator(LogicalKeyboardKey.space): _stepForward,
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).maybePop(),
    };

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.readerBackground,
          body: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerDown: (_) => _scheduleAutoTurn(),
                  child: _buildPages(source),
                ),
              ),
              if (_brightness < 0.999 || _warmth > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_brightness < 0.999)
                          ColoredBox(
                            color: Colors.black.withValues(
                              alpha: 1 - _brightness,
                            ),
                          ),
                        if (_warmth > 0)
                          ColoredBox(
                            color: const Color(0xFFFFB46A)
                                .withValues(alpha: _warmth),
                          ),
                      ],
                    ),
                  ),
                ),
              _buildTopBar(),
              _buildBottomBar(),
              _buildNextVolumeCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPages(ComicSource source) {
    if (_mode == ReadingMode.horizontal) {
      final controller = _pageController;
      if (controller == null) return const SizedBox();
      return PaperPageView(
        key: ObjectKey(controller),
        controller: controller,
        source: source,
        rightToLeft: _rightToLeft,
        spreads: _usesSpreads ? _spreads : null,
        background: AppColors.readerBackground,
        paperAnimation: _pageTurnAnimation == PageTurnAnimation.paper,
        scrollable: !_locked,
        cropController: _activeCrop,
        onSettled: _handleHorizontalSettled,
        wrapPage: (child, onZoomChanged) => _ZoomablePage(
          onTap: _toggleChrome,
          // While locked, any tap toggles the menu instead of turning pages.
          // 锁定后，点按任意位置都只切换菜单，不再翻页。
          onTapLeft: _locked
              ? null
              : () => _rightToLeft ? _goNext() : _goPrevious(),
          onTapRight: _locked
              ? null
              : () => _rightToLeft ? _goPrevious() : _goNext(),
          sideFraction: _tapZoneWidth.fraction,
          onZoomChanged: onZoomChanged,
          child: child,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureVerticalLayout(constraints.maxWidth, constraints.maxHeight);
        final controller = _verticalController;
        if (controller == null) return const SizedBox();
        return ListView.builder(
          controller: controller,
          physics: _locked ? const NeverScrollableScrollPhysics() : null,
          padding: EdgeInsets.zero,
          scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
          itemCount: _pageCount,
          itemExtentBuilder: (index, _) =>
              _pageOffsets[index + 1] - _pageOffsets[index],
          itemBuilder: (context, index) {
            final height =
                _pageOffsets[index + 1] - _pageOffsets[index] - _pageGap;
            return Padding(
              padding: const EdgeInsets.only(bottom: _pageGap),
              child: SizedBox(
                width: constraints.maxWidth,
                height: height,
                child: _ZoomablePage(
                  key: ValueKey('v-$index'),
                  onTap: _toggleChrome,
                  // Tapping the side zones scrolls one screen, mirroring the
                  // left/right page turns of horizontal mode.
                  // 点按两侧区域滚动一屏，与横向模式的左右翻页保持一致。
                  onTapLeft: _locked
                      ? null
                      : () => _scrollVertical(_rightToLeft ? 1 : -1),
                  onTapRight: _locked
                      ? null
                      : () => _scrollVertical(_rightToLeft ? -1 : 1),
                  sideFraction: _tapZoneWidth.fraction,
                  child: ComicPageImage(
                    source: source,
                    index: index,
                    cropController: _activeCrop,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTopBar() {
    final bookmarked = _book.isBookmarked(_currentPage);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_chromeVisible,
        child: AnimatedOpacity(
          opacity: _chromeVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedSlide(
            offset: _chromeVisible ? Offset.zero : const Offset(0, -0.35),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Container(
              padding: const EdgeInsets.only(bottom: 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.8, 1.0],
                  colors: [
                    Color(0xFF000000),
                    Color(0xFF000000),
                    Color(0x00000000),
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 58,
                      child: Row(
                        children: [
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 20,
                            ),
                            tooltip: '返回书架',
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _book.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Color(0x99000000),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _topSubtitleText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                    shadows: const [
                                      Shadow(
                                        color: Color(0x99000000),
                                        blurRadius: 5,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _toggleBookmark,
                            tooltip: bookmarked ? '移除书签' : '添加书签',
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(scale: animation, child: child),
                              child: Icon(
                                bookmarked
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_border_rounded,
                                key: ValueKey(bookmarked),
                                size: 22,
                                color: bookmarked ? AppColors.accent : Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _openNavigation,
                            icon: const Icon(Icons.toc_rounded, size: 22),
                            tooltip: '目录、书签与缩略图',
                          ),
                          if (_mode == ReadingMode.horizontal)
                            IconButton(
                              onPressed: _toggleDirection,
                              icon: Icon(
                                Icons.swap_horiz_rounded,
                                size: 22,
                                color: _rightToLeft
                                    ? AppColors.accent
                                    : Colors.white,
                              ),
                              tooltip: _rightToLeft ? '从右向左阅读' : '从左向右阅读',
                            ),
                          IconButton(
                            onPressed: _openReaderSettings,
                            icon: const Icon(Icons.tune_rounded, size: 22),
                            tooltip: '阅读设置',
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                    _buildReadingTimeBadge(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadingTimeBadge() {
    return ListenableBuilder(
      listenable: _repository,
      builder: (context, _) {
        final stats = _repository.stats;
        final now = DateTime.now();
        final todaySeconds = stats.secondsToday(now);
        final goalMinutes = stats.dailyGoalMinutes;
        final goalMet = stats.isGoalMetOn(now);
        final accent = goalMet ? AppColors.success : AppColors.accent;
        final label = goalMinutes > 0
            ? '今日已看 ${formatCompactReadingDuration(todaySeconds)} / $goalMinutes 分钟${goalMet ? ' · 已达标' : ''}'
            : '今日已看 ${formatCompactReadingDuration(todaySeconds)}';

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openReadingStats,
              borderRadius: BorderRadius.circular(20),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: goalMet
                        ? AppColors.success.withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      goalMet ? Icons.verified_rounded : Icons.schedule_rounded,
                      size: 12.5,
                      color: accent,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final maxPage = _pageCount > 1 ? (_pageCount - 1).toDouble() : 1.0;
    final value = _pageCount > 0
        ? _currentPage.clamp(0, _pageCount - 1).toDouble()
        : 0.0;
    final canGoPrevious = _usesSpreads && _spreads.isNotEmpty
        ? spreadIndexForPage(_spreads, _currentPage) > 0
        : _currentPage > 0;
    final canGoNext = _usesSpreads && _spreads.isNotEmpty
        ? spreadIndexForPage(_spreads, _currentPage) + 1 < _spreads.length
        : _currentPage < _pageCount - 1;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !_chromeVisible,
        child: AnimatedOpacity(
          opacity: _chromeVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: AnimatedSlide(
            offset: _chromeVisible ? Offset.zero : const Offset(0, 0.35),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xF2000000)],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 28, 8, 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2.5,
                                trackShape: const RoundedRectSliderTrackShape(),
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 16,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Slider(
                                    value: value,
                                    max: maxPage,
                                    onChangeStart: _pageCount > 1
                                        ? (_) {
                                            _sliderActive = true;
                                            _hideTimer?.cancel();
                                          }
                                        : null,
                                    onChanged: _pageCount > 1
                                        ? (value) => _goToPage(
                                            value.round(),
                                            animate: false,
                                            revealChrome: true,
                                          )
                                        : null,
                                    onChangeEnd: _pageCount > 1
                                        ? (_) {
                                            _sliderActive = false;
                                            _scheduleChromeHide();
                                            _scheduleAutoTurn();
                                          }
                                        : null,
                                  ),
                                  if (_book.bookmarks.isNotEmpty)
                                    Positioned.fill(
                                      child: SliderTicks(
                                        fractions: [
                                          for (final bookmark
                                              in _book.bookmarks)
                                            bookmark.page / maxPage,
                                        ],
                                        color: AppColors.accent,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          _ReaderIconButton(
                            icon: _locked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            tooltip: _locked ? '解除触摸锁定' : '锁定触摸翻页',
                            active: _locked,
                            onPressed: _toggleLock,
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            const Spacer(),
                            _ReaderIconButton(
                              icon: Icons.chevron_left_rounded,
                              tooltip: '上一页',
                              onPressed: canGoPrevious
                                  ? () => _goPrevious(revealChrome: true)
                                  : null,
                            ),
                            const SizedBox(width: 6),
                            TextButton(
                              onPressed: _pageCount > 1
                                  ? _showJumpDialog
                                  : null,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.06,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 6,
                                ),
                                minimumSize: const Size(0, 38),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                _pageCounterText,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            _ReaderIconButton(
                              icon: Icons.chevron_right_rounded,
                              tooltip: '下一页',
                              onPressed: canGoNext
                                  ? () => _goNext(revealChrome: true)
                                  : null,
                            ),
                            const Spacer(),
                            if (_mode == ReadingMode.horizontal &&
                                _pageCount > 1) ...[
                              _ReaderIconButton(
                                icon: Icons.import_contacts_rounded,
                                tooltip: _doublePage ? '关闭双页模式' : '开启双页模式',
                                active: _doublePage,
                                onPressed: _toggleDoublePage,
                              ),
                              const SizedBox(width: 4),
                            ],
                            _ReaderIconButton(
                              icon: _mode == ReadingMode.horizontal
                                  ? Icons.swap_vert_rounded
                                  : Icons.swap_horiz_rounded,
                              tooltip: _mode == ReadingMode.horizontal
                                  ? '切换为纵向滚动'
                                  : '切换为横向翻页',
                              onPressed: _toggleMode,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({
    required this.child,
    required this.onTap,
    required this.onTapLeft,
    required this.onTapRight,
    this.sideFraction = 0.28,
    this.onZoomChanged,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onTapLeft;
  final VoidCallback? onTapRight;

  /// Width of each page-turning side zone, as a fraction of the page.
  /// 两侧翻页区域各占页面宽度的比例。
  final double sideFraction;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final TransformationController _controller = TransformationController();
  Offset? _doubleTapPosition;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTransform);
  }

  void _handleTransform() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
      widget.onZoomChanged?.call(zoomed);
    }
  }

  void _handleTap(TapUpDetails details) {
    if (widget.onTapLeft == null || widget.onTapRight == null) {
      widget.onTap();
      return;
    }
    final width = context.size?.width ?? 0;
    final side = widget.sideFraction.clamp(0.1, 0.45);
    final x = details.localPosition.dx;
    if (x < width * side) {
      widget.onTapLeft!();
    } else if (x > width * (1 - side)) {
      widget.onTapRight!();
    } else {
      widget.onTap();
    }
  }

  void _toggleZoom() {
    if (_zoomed) {
      _controller.value = Matrix4.identity();
    } else {
      final size = context.size ?? Size.zero;
      final focal =
          _doubleTapPosition ?? Offset(size.width / 2, size.height / 2);
      const scale = 2.4;
      final matrix = Matrix4.identity()
        ..translateByDouble(
          -focal.dx * (scale - 1),
          -focal.dy * (scale - 1),
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1);
      _controller.value = matrix;
    }
  }

  @override
  void dispose() {
    if (_zoomed) widget.onZoomChanged?.call(false);
    _controller
      ..removeListener(_handleTransform)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _handleTap,
      onDoubleTapDown: (details) => _doubleTapPosition = details.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 5,
        panEnabled: _zoomed,
        scaleEnabled: true,
        clipBehavior: Clip.hardEdge,
        child: SizedBox.expand(
          child: PageRenderScale(controller: _controller, child: widget.child),
        ),
      ),
    );
  }
}

class _NextVolumeCard extends StatelessWidget {
  const _NextVolumeCard({required this.title, required this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_stories_rounded,
            size: 22,
            color: AppColors.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '已读完本卷',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '下一卷：$title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: const Color(0xFF2A1500),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('继续阅读'),
          ),
        ],
      ),
    );
  }
}

class _ReaderIconButton extends StatelessWidget {
  const _ReaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 24),
      style: IconButton.styleFrom(
        foregroundColor: active ? AppColors.accent : Colors.white,
        disabledForegroundColor: Colors.white24,
        backgroundColor: active
            ? AppColors.accent.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.07),
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.03),
        minimumSize: const Size(40, 40),
        maximumSize: const Size(40, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.readerBackground,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 54),
                const SizedBox(height: 22),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: const LinearProgressIndicator(
                      minHeight: 5,
                      backgroundColor: Color(0x22FFFFFF),
                      valueColor: AlwaysStoppedAnimation(AppColors.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '正在打开漫画…',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.readerBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: Colors.white70,
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      child: const Icon(
                        Icons.menu_book_rounded,
                        color: Colors.white30,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.6,
                        color: Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('重试'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('返回书架'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JumpPageDialog extends StatefulWidget {
  const _JumpPageDialog({
    required this.currentPage,
    required this.pageCount,
  });

  final int currentPage;
  final int pageCount;

  @override
  State<_JumpPageDialog> createState() => _JumpPageDialogState();
}

class _JumpPageDialogState extends State<_JumpPageDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.currentPage + 1}');
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.pageCount <= 0) {
      Navigator.of(context).pop();
      return;
    }
    final parsed = int.tryParse(_controller.text.trim());
    Navigator.of(context).pop(parsed?.clamp(1, widget.pageCount));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('跳转到页码'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: '页码 (1 - ${widget.pageCount})',
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('跳转'),
        ),
      ],
    );
  }
}
