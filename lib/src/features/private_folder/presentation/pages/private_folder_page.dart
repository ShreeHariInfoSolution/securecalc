import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/features/chat/domain/models/server_models.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import '../widgets/folder_card.dart';
import '../widgets/media_grid_item.dart';
import '../widgets/file_preview_dialog.dart';
import '../widgets/private_folder_overview.dart';
import '../widgets/private_folder_header.dart';
import '../widgets/private_folder_item_grid.dart';
import '../widgets/private_folder_item_list.dart';
import '../models/vault_folder_descriptor.dart';
import '../../../../core/utils/app_toast.dart';

class _FolderState {
  final String folderKey;
  final List<UploadItemModel> items;
  int page;
  int limit;
  int total;
  bool isLoading;
  bool isFetchingMore;
  bool hasMore;
  String? error;

  _FolderState({
    required this.folderKey,
    List<UploadItemModel>? items,
    this.page = 1,
    this.limit = 20,
    this.total = 0,
    this.isLoading = false,
    this.isFetchingMore = false,
    this.hasMore = true,
    this.error,
  }) : items = items ?? [];
}

class PrivateFolderPage extends StatefulWidget {
  final String? initialFolder;

  const PrivateFolderPage({
    super.key,
    this.initialFolder,
  });

  @override
  State<PrivateFolderPage> createState() => _PrivateFolderPageState();
}

class _PrivateFolderPageState extends State<PrivateFolderPage> {
  int _selectedTabIndex = 0; // 0 = Overview, 1 = Image, 2 = Video, 3 = Audio, 4 = Doc
  bool _isUploading = false;
  final ImagePicker _imagePicker = ImagePicker();
  final ScrollController _scrollController = ScrollController();

  final Map<String, _FolderState> _folderStates = {
    'image': _FolderState(folderKey: 'image'),
    'video': _FolderState(folderKey: 'video'),
    'audio': _FolderState(folderKey: 'audio'),
    'doc': _FolderState(folderKey: 'doc'),
  };

  static const List<VaultFolderDescriptor> _folderMeta = [
    VaultFolderDescriptor(
      key: 'image',
      title: 'Photos & Images',
      subtitle: 'Photos, Screenshots & Media',
      icon: CupertinoIcons.photo_on_rectangle,
      color: Color(0xFFAF52DE),
    ),
    VaultFolderDescriptor(
      key: 'video',
      title: 'Videos',
      subtitle: 'Video Clips & Recordings',
      icon: CupertinoIcons.videocam_circle_fill,
      color: Color(0xFF007AFF),
    ),
    VaultFolderDescriptor(
      key: 'audio',
      title: 'Audio Recordings',
      subtitle: 'Voice Notes, Songs & Clips',
      icon: CupertinoIcons.waveform_circle_fill,
      color: Color(0xFFFF9500),
    ),
    VaultFolderDescriptor(
      key: 'doc',
      title: 'Documents',
      subtitle: 'PDFs, Files & Spreadsheets',
      icon: CupertinoIcons.doc_on_doc_fill,
      color: Color(0xFF34C759),
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialFolder != null) {
      final idx = ['image', 'video', 'audio', 'doc'].indexOf(widget.initialFolder!);
      if (idx != -1) {
        _selectedTabIndex = idx + 1;
      }
    }

    _scrollController.addListener(_onScroll);
    _loadInitialDataAllFolders();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _selectedTabIndex == 0) return;

    final currentFolder = _folderMeta[_selectedTabIndex - 1].key;
    final state = _folderStates[currentFolder];
    if (state == null) return;

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 250) {
      if (!state.isFetchingMore && !state.isLoading && state.hasMore) {
        _loadNextPage(currentFolder);
      }
    }
  }

  Future<void> _loadInitialDataAllFolders() async {
    for (final meta in _folderMeta) {
      final key = meta.key;
      _fetchFolderData(key, page: 1, isRefresh: true);
    }
  }

  Future<void> _fetchFolderData(String folderKey, {int page = 1, bool isRefresh = false}) async {
    final state = _folderStates[folderKey];
    if (state == null) return;

    if (isRefresh) {
      setState(() {
        state.isLoading = true;
        state.error = null;
      });
    }

    try {
      final res = await ServerApiService.instance.getUploads(
        folder: folderKey,
        page: page,
        limit: state.limit,
      );

      if (mounted) {
        setState(() {
          state.isLoading = false;
          state.isFetchingMore = false;
          state.page = res.page;
          state.total = res.total > 0 ? res.total : (isRefresh ? res.items.length : state.total);

          if (isRefresh) {
            state.items.clear();
            state.items.addAll(res.items);
          } else {
            state.items.addAll(res.items);
          }

          state.hasMore = state.items.length < state.total && res.items.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('[PrivateFolder] Fetch error for $folderKey: $e');
      if (mounted) {
        setState(() {
          state.isLoading = false;
          state.isFetchingMore = false;
          state.error = e.toString();
        });
      }
    }
  }

  Future<void> _loadNextPage(String folderKey) async {
    final state = _folderStates[folderKey];
    if (state == null || state.isFetchingMore || !state.hasMore) return;

    setState(() {
      state.isFetchingMore = true;
    });

    await _fetchFolderData(folderKey, page: state.page + 1, isRefresh: false);
  }

  Future<void> _handleRefresh() async {
    if (_selectedTabIndex == 0) {
      await _loadInitialDataAllFolders();
    } else {
      final folderKey = _folderMeta[_selectedTabIndex - 1].key;
      await _fetchFolderData(folderKey, page: 1, isRefresh: true);
    }
  }

  void _showUploadOptions() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Add to Private Vault'),
        message: const Text('Files uploaded here are isolated in your encrypted storage.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickAndUploadMedia(ImageSource.camera);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.camera, size: 20),
                SizedBox(width: 8),
                Text('Take Photo / Video'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickAndUploadMedia(ImageSource.gallery);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.photo, size: 20),
                SizedBox(width: 8),
                Text('Choose Photo / Video'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickAndUploadDocument(FileType.audio);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.music_note_2, size: 20),
                SizedBox(width: 8),
                Text('Upload Audio File'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickAndUploadDocument(FileType.any);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.doc_on_doc, size: 20),
                SizedBox(width: 8),
                Text('Upload Document / Any File'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickAndUploadMedia(ImageSource source) async {
    AppPreferences.isPickerActive = true;
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (file != null) {
        await _uploadFileToVault(File(file.path));
      }
    } catch (e) {
      AppToast.show('Error selecting image: $e');
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _pickAndUploadDocument(FileType type) async {
    AppPreferences.isPickerActive = true;
    try {
      final files = await FilePicker.pickFiles(type: type);
      if (files.isEmpty) return;
      final picked = files.first;
      final path = picked.path;
      if (path != null && path.isNotEmpty) {
        await _uploadFileToVault(File(path));
      }
    } catch (e) {
      AppToast.show('Error selecting file: $e');
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _uploadFileToVault(File file) async {
    setState(() => _isUploading = true);

    try {
      final uploadedItem = await ServerApiService.instance.uploadVaultFile(file);

      if (uploadedItem != null) {
        AppToast.show('File uploaded to vault successfully.');

        // Infer target folder
        String targetFolder = 'doc';
        if (uploadedItem.isImage) {
          targetFolder = 'image';
        } else if (uploadedItem.isVideo) {
          targetFolder = 'video';
        } else if (uploadedItem.isAudio) {
          targetFolder = 'audio';
        }

        final state = _folderStates[targetFolder];
        if (state != null) {
          setState(() {
            state.items.insert(0, uploadedItem);
            state.total += 1;
          });
        }
      } else {
        AppToast.show('Upload failed. Please check your connection.');
      }
    } catch (e) {
      AppToast.show('Upload error: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                PrivateFolderHeader(
                  isDark: isDark,
                  onBack: () => Navigator.pop(context),
                  onUpload: _showUploadOptions,
                ),
                _buildSegmentedControl(isDark),
                Expanded(
                  child: RefreshIndicator.adaptive(
                    onRefresh: _handleRefresh,
                    child: _selectedTabIndex == 0
                        ? _buildOverviewTab(isDark)
                        : _buildFolderItemsTab(isDark),
                  ),
                ),
              ],
            ),
          ),
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoActivityIndicator(radius: 16),
                      SizedBox(height: 16),
                      Text(
                        'Uploading to Private Vault...',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                ),
              ),
              child: Icon(
                CupertinoIcons.chevron_left,
                color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Private Folder',
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  'Encrypted Storage Vault',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _showUploadOptions,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFAF52DE), Color(0xFF007AFF)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFAF52DE).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(CupertinoIcons.add, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Upload',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<int>(
          groupValue: _selectedTabIndex,
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
          thumbColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          padding: const EdgeInsets.all(3),
          children: const {
            0: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text('All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            1: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text('Photos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            2: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text('Videos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            3: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text('Audio', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            4: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text('Docs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          },
          onValueChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedTabIndex = val;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildOverviewTab(bool isDark) {
    final recentItems = _getAllRecentItems();

    final Map<String, int> totalCounts = {
      for (final state in _folderStates.values) state.folderKey: state.total,
    };

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        PrivateFolderOverview(
          isDark: isDark,
          descriptors: _folderMeta,
          totalCounts: totalCounts,
          recentItems: recentItems,
          onFolderTap: (index) {
            setState(() {
              _selectedTabIndex = index;
            });
          },
          onItemTap: (item) => FilePreviewDialog.show(
            context,
            item,
            onItemDeleted: () => _handleRefresh(),
          ),
        ),
      ],
    );
  }

  List<UploadItemModel> _getAllRecentItems() {
    final allRecentItems = <UploadItemModel>[];
    for (final state in _folderStates.values) {
      allRecentItems.addAll(state.items);
    }
    allRecentItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return allRecentItems;
  }

  int _getTotalItemCount() {
    int total = 0;
    for (final state in _folderStates.values) {
      total += state.total;
    }
    return total;
  }

  Widget _buildCombinedRecentItems(bool isDark, List<UploadItemModel> allRecentItems) {
    if (allRecentItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final recentPreview = allRecentItems.take(10).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          itemCount: recentPreview.length,
          itemBuilder: (context, index) {
            final item = recentPreview[index];
            return MediaGridItem(
              item: item,
              isSquareGrid: true,
              onTap: () => FilePreviewDialog.show(
                context,
                item,
                onItemDeleted: () => _handleRefresh(),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFolderItemsTab(bool isDark) {
    final meta = _folderMeta[_selectedTabIndex - 1];
    final folderKey = meta.key;
    final state = _folderStates[folderKey];

    if (state == null || (state.isLoading && state.items.isEmpty)) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }

    if (state.error != null && state.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.exclamationmark_circle, color: CupertinoColors.systemRed, size: 48),
              const SizedBox(height: 12),
              Text(
                'Failed to load ${meta.title}',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              CupertinoButton.filled(
                onPressed: () => _fetchFolderData(folderKey, page: 1, isRefresh: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                meta.icon,
                size: 56,
                color: meta.color.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No Data in Folder',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'You have no ${meta.title.toLowerCase()} in this folder yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              CupertinoButton(
                color: meta.color,
                borderRadius: BorderRadius.circular(12),
                onPressed: _showUploadOptions,
                child: const Text('Upload Now', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    final isListStyle = folderKey == 'audio' || folderKey == 'doc';

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: isListStyle
              ? PrivateFolderItemList(
                  items: state.items,
                  onItemTap: (item) => FilePreviewDialog.show(
                    context,
                    item,
                    onItemDeleted: () => _fetchFolderData(folderKey, page: 1, isRefresh: true),
                  ),
                )
              : PrivateFolderItemGrid(
                  items: state.items,
                  onItemTap: (item) => FilePreviewDialog.show(
                    context,
                    item,
                    onItemDeleted: () => _fetchFolderData(folderKey, page: 1, isRefresh: true),
                  ),
                ),
        ),
        if (state.isFetchingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CupertinoActivityIndicator(radius: 12),
              ),
            ),
          ),
        if (!state.hasMore && state.items.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'All ${state.total} items loaded',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF6C6C70) : const Color(0xFF8E8E93),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
