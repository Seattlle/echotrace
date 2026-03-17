import 'package:flutter/material.dart';
import '../services/database_service.dart';

class YearSelectionResult {
  final int? year;
  final bool confirmed;

  const YearSelectionResult({required this.year, required this.confirmed});
}

mixin YearSelectionMixin<T extends StatefulWidget> on State<T> {
  bool _isLoadingYears = true;
  String? _yearLoadError;
  List<int> _availableYears = const [];
  int? _selectedYear;
  bool _yearConfirmed = false;
  bool _autoPrompted = false;

  DatabaseService get yearDatabaseService;

  int? get selectedYear => _selectedYear;
  bool get yearConfirmed => _yearConfirmed;

  @protected
  void initYearSelection({bool autoPrompt = true}) {
    _loadAvailableYears();
    if (!autoPrompt) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _autoPrompted) return;
      _autoPrompted = true;
      await ensureYearSelection();
    });
  }

  @protected
  Future<void> refreshAvailableYears() async {
    await _loadAvailableYears();
  }

  Future<void> _loadAvailableYears() async {
    setState(() {
      _isLoadingYears = true;
      _yearLoadError = null;
    });
    try {
      final years = await yearDatabaseService.getAvailableMessageYears();
      if (!mounted) return;
      setState(() {
        _availableYears = years;
        if (_selectedYear != null && !_availableYears.contains(_selectedYear)) {
          _selectedYear = null;
        }
        if (_selectedYear == null && _yearConfirmed) {
          _yearConfirmed = false;
        }
        _isLoadingYears = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _availableYears = const [];
        _selectedYear = null;
        _yearConfirmed = false;
        _yearLoadError = '年份加载失败';
        _isLoadingYears = false;
      });
    }
  }

  @protected
  Future<bool> ensureYearSelection() async {
    if (_yearConfirmed) return true;

    if (!_isLoadingYears && _availableYears.isEmpty && _yearLoadError == null) {
      setState(() {
        _isLoadingYears = true;
      });
    }

    bool loadRequested = false;
    final result = await showModalBottomSheet<YearSelectionResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        int? tempSelection = _selectedYear;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                if (!loadRequested) {
                  loadRequested = true;
                  Future.microtask(() async {
                    await _loadAvailableYears();
                    if (context.mounted) {
                      setSheetState(() {});
                    }
                  });
                }
                final isLoading = _isLoadingYears;
                final hasYears = _availableYears.isNotEmpty;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '选择时间范围',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _yearLoadError != null
                          ? '年份加载失败，仅支持全部时间'
                          : isLoading
                              ? '正在加载可用年份...'
                              : '仅列出有消息的年份',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _yearLoadError != null
                            ? Colors.orange
                            : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            RadioListTile<int?>(
                              value: null,
                              groupValue: tempSelection,
                              onChanged: (value) {
                                setSheetState(() {
                                  tempSelection = value;
                                });
                              },
                              title: const Text('全部时间'),
                              dense: true,
                            ),
                            if (hasYears)
                              for (final year in _availableYears.reversed)
                                RadioListTile<int?>(
                                  value: year,
                                  groupValue: tempSelection,
                                  onChanged: (value) {
                                    setSheetState(() {
                                      tempSelection = value;
                                    });
                                  },
                                  title: Text('$year年'),
                                  dense: true,
                                ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(
                              const YearSelectionResult(
                                year: null,
                                confirmed: false,
                              ),
                            );
                          },
                          child: const Text('取消'),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: isLoading
                              ? null
                              : () {
                                  Navigator.of(context).pop(
                                    YearSelectionResult(
                                      year: tempSelection,
                                      confirmed: true,
                                    ),
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF07C160),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('确定'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (!mounted) return false;
    if (result == null || !result.confirmed) {
      return false;
    }

    setState(() {
      _selectedYear = result.year;
      _yearConfirmed = true;
    });
    return true;
  }
}
