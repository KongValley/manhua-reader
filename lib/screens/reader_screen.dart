import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../formats/comic_source.dart';
import '../formats/comic_source_factory.dart';
import '../models/comic_book.dart';
import '../models/reader_settings.dart';
import '../models/toc_entry.dart';
import '../services/library_repository.dart';
import '../services/pdf_password_cache.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/pagination.dart';
import '../widgets/book_cover.dart';
import '../widgets/bookmark_editor_dialog.dart';
import '../widgets/paper_page_view.dart';
import '../widgets/pdf_password_dialog.dart';
import '../widgets/reader_navigation_sheet.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({required this.book, required this.repository, super.key});

  final ComicBook book;
  final LibraryRepository repository;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  static const double _pageGap = 6;

  ComicSource? _source;
  Object? _openError;
  bool _loading = true;

  late ReadingMode _mode;
  late bool _rightToLeft;
  late bool _doublePage;
  int _pageCount = 0;
  int _currentPage = 0;
  List<List<int>> _spreads = const [];
  Future<List<TocEntry>>? _tocFuture;

  PageController? _pageController;
  int? _pendingHorizontalPage;
  ScrollController? _verticalController;
  double _verticalWidth = -1;
  List<double> _pageOffsets = const [];

  bool _chromeVisible = true;
  bool _sliderActive = false;
  Timer? _hideTimer;
  Timer? _persistTimer;

  LibraryRepository get _repository => widget.repository;
  ComicBook get _book => widget.book;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mode = _repository.settings.mode;
    _rightToLeft = _repository.settings.rightToLeft;
    _doublePage = _repository.settings.doublePage;
    _currentPage = _book.safeLastPage;
    _enterImmersiveMode();
    _loadSource();
  }

  Future<void> _loadSource() async {
    try {
      var passwordAttempts = 0;
      String? lastPassword;
      Future<String?> passwordProvider() async {
        passwordAttempts++;
        if (passwordAttempts == 1) {
          final cached = PdfPasswordCache.get(_book.filePath);
          if (cached != null) {
            lastPassword = cached;
            return cached;
          }
        }
        if (!mounted) return null;
        final password = await showPdfPasswordDialog(
          context,
          fileName: _book.title,
          errorText: passwordAttempts > 1 ? '密码不正确，请重试' : null,
        );
        if (password != null) lastPassword = password;
        return password;
      }

      final source = await ComicSourceFactory.open(
        _book,
        passwordProvider: passwordProvider,
      );
      if (!mounted) {
        await source.dispose();
        return;
      }
      PdfPasswordCache.put(_book.filePath, lastPassword);
      final pageCount = source.pageCount;
      if (_book.pageCount != pageCount) {
        _book.pageCount = pageCount;
        _book.lastPage = clampPage(_book.lastPage, pageCount);
        _book.bookmarks.removeWhere(
          (bookmark) => bookmark.page < 0 || bookmark.page >= pageCount,
        );
      }
      setState(() {
        _source = source;
        _pageCount = pageCount;
        _currentPage = clampPage(_currentPage, pageCount);
        _spreads = buildSpreads(pageCount);
        _tocFuture = source.loadToc();
        _pageController = _startingPageController();
        _loading = false;
      });
      _repository.updateProgress(_book, _currentPage);
      _scheduleChromeHide();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString();
      if (_book.format == ComicFormat.pdf &&
          (message.contains('密码') || message.contains('取消'))) {
        PdfPasswordCache.remove(_book.filePath);
      }
      setState(() {
        _openError = error;
        _loading = false;
      });
    }
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _persistProgressNow();
      unawaited(_repository.flush());
    } else if (state == AppLifecycleState.resumed) {
      _enterImmersiveMode();
    }
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
    setState(() => _currentPage = page);
    _persistProgressSoon();
    _scheduleChromeHide();
  }

  void _handleSpreadChanged(int index) {
    if (index < 0 || index >= _spreads.length) return;
    final spread = _spreads[index];
    if (spread.contains(_currentPage)) return;
    setState(() => _currentPage = spread.first);
    _persistProgressSoon();
    _scheduleChromeHide();
  }

  void _persistProgressSoon() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 350), () {
      _persistTimer = null;
      if (mounted) _persistProgressNow();
    });
  }

  void _persistProgressNow() {
    _repository.updateProgress(_book, _currentPage);
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
    if (_pageCount <= 0) return;
    final target = clampPage(page, _pageCount);
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

    if (target == _currentPage) return;
    setState(() => _currentPage = target);
    _persistProgressSoon();
    final controller = _verticalController;
    if (controller == null ||
        !controller.hasClients ||
        target >= _pageOffsets.length) {
      return;
    }
    final offset = _pageOffsets[target];
    if (animate) {
      controller.animateTo(
        offset,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      controller.jumpTo(offset);
    }
  }

  void _goPrevious({bool revealChrome = false}) {
    if (_usesSpreads && _spreads.isNotEmpty) {
      final index = spreadIndexForPage(_spreads, _currentPage);
      if (index > 0) {
        _goToPage(_spreads[index - 1].first, revealChrome: revealChrome);
      }
      return;
    }
    if (_currentPage > 0) {
      _goToPage(_currentPage - 1, revealChrome: revealChrome);
    }
  }

  void _goNext({bool revealChrome = false}) {
    if (_usesSpreads && _spreads.isNotEmpty) {
      final index = spreadIndexForPage(_spreads, _currentPage);
      if (index + 1 < _spreads.length) {
        _goToPage(_spreads[index + 1].first, revealChrome: revealChrome);
      }
      return;
    }
    if (_currentPage < _pageCount - 1) {
      _goToPage(_currentPage + 1, revealChrome: revealChrome);
    }
  }

  void _toggleMode() {
    final next = _mode == ReadingMode.horizontal
        ? ReadingMode.vertical
        : ReadingMode.horizontal;
    _repository.setReadingMode(next);
    final oldVertical = _verticalController;
    final oldPage = _pageController;
    setState(() {
      _mode = next;
      _pendingHorizontalPage = null;
      _verticalWidth = -1;
      _pageOffsets = const [];
      if (next == ReadingMode.horizontal) {
        _verticalController = null;
        _pageController = _startingPageController();
      } else {
        _pageController = null;
      }
    });
    _disposeLater(oldPage);
    _disposeLater(oldVertical);
    _keepChromeVisible();
  }

  void _toggleDirection() {
    _repository.setRightToLeft(!_rightToLeft);
    final old = _pageController;
    setState(() {
      _rightToLeft = !_rightToLeft;
      _pendingHorizontalPage = null;
      _pageController = _startingPageController();
    });
    _disposeLater(old);
    _keepChromeVisible();
  }

  void _toggleDoublePage() {
    if (_pageCount <= 1) return;
    final next = !_doublePage;
    _repository.setDoublePage(next);
    final oldPage = _pageController;
    final oldVertical = _verticalController;
    setState(() {
      _doublePage = next;
      _pendingHorizontalPage = null;
      if (_mode != ReadingMode.horizontal) {
        _mode = ReadingMode.horizontal;
        _repository.setReadingMode(ReadingMode.horizontal);
        _verticalController = null;
        _verticalWidth = -1;
        _pageOffsets = const [];
      }
      _pageController = _startingPageController();
    });
    _disposeLater(oldPage);
    _disposeLater(oldVertical);
    _keepChromeVisible();
    if (!next) {
      _showReaderNotice('双页模式已关闭');
    } else if (MediaQuery.sizeOf(context).width < 600) {
      _showReaderNotice('双页模式已开启（横屏效果更好）');
    } else {
      _showReaderNotice('双页模式已开启');
    }
  }

  void _toggleBookmark() {
    final page = _currentPage;
    final wasBookmarked = _book.isBookmarked(page);
    _repository.toggleBookmark(_book, page);
    setState(() {});
    _keepChromeVisible();
    if (wasBookmarked) {
      _showReaderNotice('已移除书签');
    } else {
      _showReaderNotice(
        '已添加书签 · 第 ${page + 1} 页',
        action: SnackBarAction(
          label: '命名',
          onPressed: () => _editBookmark(page),
        ),
      );
    }
  }

  Future<void> _editBookmark(int page) async {
    final existing = _book.bookmarkAt(page);
    final result = await showBookmarkEditorDialog(
      context,
      page: page,
      existing: existing,
    );
    if (!mounted || result == null) return;
    _repository.setBookmark(
      _book,
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
  }

  void _disposeLater(ScrollController? controller) {
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
  }

  void _ensureVerticalLayout(double width) {
    if (width <= 0 || _source == null) return;
    if (width == _verticalWidth && _verticalController != null) return;

    final offsets = List<double>.filled(_pageCount, 0);
    var cursor = 0.0;
    for (var i = 0; i < _pageCount; i++) {
      offsets[i] = cursor;
      final size = _source!.pageSize(i);
      final height = width * size.height / size.width;
      cursor += height + _pageGap;
    }

    final old = _verticalController;
    if (old != null) {
      old.removeListener(_onVerticalScroll);
      _disposeLater(old);
    }

    _verticalWidth = width;
    _pageOffsets = offsets;
    final controller = ScrollController(
      initialScrollOffset: offsets.isEmpty ? 0 : offsets[_currentPage],
    );
    controller.addListener(_onVerticalScroll);
    _verticalController = controller;
  }

  void _onVerticalScroll() {
    final controller = _verticalController;
    if (controller == null || !controller.hasClients || _pageOffsets.isEmpty) {
      return;
    }
    final offset = controller.offset;
    var page = 0;
    var low = 0;
    var high = _pageOffsets.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (_pageOffsets[mid] <= offset + 1) {
        page = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (page != _currentPage) {
      setState(() => _currentPage = page);
      _persistProgressSoon();
    }
  }

  Future<void> _showJumpDialog() async {
    _hideTimer?.cancel();
    final controller = TextEditingController(text: '${_currentPage + 1}');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳转到页面'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            labelText: '页码',
            helperText: '共 $_pageCount 页',
            suffixText: '/ $_pageCount',
          ),
          onSubmitted: (value) =>
              Navigator.of(context).pop(int.tryParse(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(controller.text.trim())),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (result != null) {
      _goToPage(result - 1, revealChrome: true);
    }
    _scheduleChromeHide();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _persistTimer?.cancel();
    _persistProgressNow();
    unawaited(_repository.flush());
    _pageController?.dispose();
    _verticalController?.dispose();
    final source = _source;
    _source = null;
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
      const SingleActivator(LogicalKeyboardKey.space): () =>
          _goNext(revealChrome: true),
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
              Positioned.fill(child: _buildPages(source)),
              _buildTopBar(),
              _buildBottomBar(),
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
        onSettled: _handleHorizontalSettled,
        wrapPage: (child, onZoomChanged) => _ZoomablePage(
          onTap: _toggleChrome,
          onTapLeft: _rightToLeft ? _goNext : _goPrevious,
          onTapRight: _rightToLeft ? _goPrevious : _goNext,
          onZoomChanged: onZoomChanged,
          child: child,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _ensureVerticalLayout(constraints.maxWidth);
        final controller = _verticalController;
        if (controller == null) return const SizedBox();
        return ListView.builder(
          controller: controller,
          padding: EdgeInsets.zero,
          scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
          itemCount: _pageCount,
          itemBuilder: (context, index) {
            final size = source.pageSize(index);
            final height = constraints.maxWidth * size.height / size.width;
            return Padding(
              padding: const EdgeInsets.only(bottom: _pageGap),
              child: SizedBox(
                width: constraints.maxWidth,
                height: height,
                child: _ZoomablePage(
                  key: ValueKey('v-$index'),
                  onTap: _toggleChrome,
                  onTapLeft: null,
                  onTapRight: null,
                  child: source.buildPage(context, index),
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
                child: SizedBox(
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
                              '${_book.format.label} · $_pageSubtitleText',
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
                      const SizedBox(width: 4),
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

  Widget _buildBottomBar() {
    final maxPage = _pageCount > 1 ? (_pageCount - 1).toDouble() : 1.0;
    final value = _currentPage.clamp(0, _pageCount - 1).toDouble();
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
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.5,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                        ),
                        child: Slider(
                          value: value,
                          max: maxPage,
                          onChangeStart: _pageCount > 1
                              ? (value) {
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
                              ? (value) {
                                  _sliderActive = false;
                                  _scheduleChromeHide();
                                }
                              : null,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            const Spacer(),
                            _ReaderIconButton(
                              icon: Icons.chevron_left_rounded,
                              tooltip: '上一页',
                              onPressed: _currentPage > 0
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
                              onPressed: _currentPage < _pageCount - 1
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
    this.onZoomChanged,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onTapLeft;
  final VoidCallback? onTapRight;
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
    final x = details.localPosition.dx;
    if (x < width * 0.28) {
      widget.onTapLeft!();
    } else if (x > width * 0.72) {
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
        child: SizedBox.expand(child: widget.child),
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
