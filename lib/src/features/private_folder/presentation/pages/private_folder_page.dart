import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:securecalc/src/core/config/app_preferences.dart';
import 'package:securecalc/src/core/utils/media_compression_service.dart';
import 'package:securecalc/src/core/widgets/shake_panic_wrapper.dart';
import 'package:securecalc/src/core/widgets/vault_edge_panel_wrapper.dart';
import 'package:securecalc/src/features/chat/domain/models/server_models.dart';
import 'package:securecalc/src/features/chat/domain/services/server_api_service.dart';
import '../widgets/media_grid_item.dart';
import '../widgets/file_preview_dialog.dart';
import '../widgets/private_folder_header.dart';
import '../../../../core/utils/app_toast.dart';

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
  // Folder Items State
  final List<UploadItemModel> _items = [];
  int _page = 1;
  final int _limit = 30;
  int _total = 0;
  bool _isLoading = false;
  bool _isFetchingMore = false;
  bool _hasMore = true;
  String? _error;

  // View Options & Navigation
  bool _isGridView = true;
  int? _currentParentId;
  List<BreadcrumbItem> _breadcrumbs = [];
  
  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Upload & Percentage Progress State
  bool _isUploading = false;
  String _uploadingFileName = '';
  int _uploadCurrentIndex = 0;
  int _uploadTotalCount = 0;
  int _uploadBytesSent = 0;
  int _uploadTotalBytes = 0;

  final ImagePicker _imagePicker = ImagePicker();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _breadcrumbs = [const BreadcrumbItem(id: null, name: 'Vault Drive')];
    _scrollController.addListener(_onScroll);
    _fetchVaultData(page: 1, isRefresh: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 250) {
      if (!_isFetchingMore && !_isLoading && _hasMore) {
        _loadNextPage();
      }
    }
  }

  Future<void> _fetchVaultData({int page = 1, bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final res = await ServerApiService.instance.getUploads(
        folder: 'image',
        parentId: _currentParentId,
        page: page,
        limit: _limit,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
          _page = res.page;
          _total = res.total;

          if (res.breadcrumbs.isNotEmpty) {
            _breadcrumbs = [
              const BreadcrumbItem(id: null, name: 'Vault Drive'),
              ...res.breadcrumbs.where((b) => b.id != null),
            ];
          } else if (_currentParentId == null) {
            _breadcrumbs = [const BreadcrumbItem(id: null, name: 'Vault Drive')];
          }

          if (isRefresh) {
            _items.clear();
            _items.addAll(res.items);
          } else {
            _items.addAll(res.items);
          }

          _hasMore = _items.length < _total && res.items.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('[PrivateVault] Fetch error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isFetchingMore || !_hasMore) return;

    setState(() {
      _isFetchingMore = true;
    });

    await _fetchVaultData(page: _page + 1, isRefresh: false);
  }

  Future<void> _handleRefresh() async {
    await _fetchVaultData(page: 1, isRefresh: true);
  }

  void _onFolderItemTap(UploadItemModel item) {
    if (item.isFolder) {
      setState(() {
        _currentParentId = item.id;
        _breadcrumbs.add(BreadcrumbItem(id: item.id, name: item.fileName));
        _searchController.clear();
        _searchQuery = '';
      });
      _fetchVaultData(page: 1, isRefresh: true);
    } else {
      FilePreviewDialog.show(
        context,
        item,
        onItemDeleted: () => _handleRefresh(),
      );
    }
  }

  void _onBreadcrumbTap(BreadcrumbItem breadcrumb, int index) {
    setState(() {
      _currentParentId = breadcrumb.id;
      _breadcrumbs = _breadcrumbs.sublist(0, index + 1);
      _searchController.clear();
      _searchQuery = '';
    });
    _fetchVaultData(page: 1, isRefresh: true);
  }

  bool _onWillPop() {
    if (_breadcrumbs.length > 1) {
      final previousBreadcrumb = _breadcrumbs[_breadcrumbs.length - 2];
      setState(() {
        _currentParentId = previousBreadcrumb.id;
        _breadcrumbs.removeLast();
        _searchController.clear();
        _searchQuery = '';
      });
      _fetchVaultData(page: 1, isRefresh: true);
      return false;
    }
    return true;
  }

  void _showCreateFolderDialog() {
    final controller = TextEditingController(text: 'New folder');
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Create New Folder'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Folder Name',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final folderName = controller.text.trim();
              Navigator.pop(ctx);
              if (folderName.isNotEmpty) {
                _createFolder(folderName);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createFolder(String name) async {
    try {
      final createdFolder = await ServerApiService.instance.createFolder(
        name: name,
        folder: 'image',
        parentId: _currentParentId,
      );

      if (createdFolder != null) {
        AppToast.show('Folder "$name" created.');
        _handleRefresh();
      } else {
        AppToast.show('Failed to create folder.', isError: true);
      }
    } catch (e) {
      AppToast.show('Error creating folder: $e', isError: true);
    }
  }

  Future<void> _renameItem(UploadItemModel item) async {
    final controller = TextEditingController(text: item.fileName);
    final newName = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(item.isFolder ? 'Rename Folder' : 'Rename File'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Enter new name',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != item.fileName) {
      final updated = await ServerApiService.instance.renameUpload(
        id: item.id,
        newName: newName,
      );
      if (updated != null) {
        AppToast.show('Renamed to "$newName"');
        _handleRefresh();
      } else {
        AppToast.show('Failed to rename item.', isError: true);
      }
    }
  }

  Future<void> _deleteItem(UploadItemModel item) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(item.isFolder ? 'Delete Folder' : 'Delete File'),
        content: Text('Are you sure you want to delete "${item.fileName}"?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await ServerApiService.instance.deleteUploadFile(
        item.id,
        filePath: item.filePath,
      );
      if (ok) {
        AppToast.show('Deleted successfully.');
      } else {
        AppToast.show('Item deleted.');
      }
      _handleRefresh();
    }
  }

  void _showUploadOptions() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Add to Private Vault'),
        message: const Text('Select photos, videos, or files to encrypt & store in your vault.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickAndUploadMultipleMedia();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.photo_on_rectangle, size: 20),
                SizedBox(width: 8),
                Text('Choose Media (Photos & Videos)'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _pickCameraMedia();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.camera, size: 20),
                SizedBox(width: 8),
                Text('Take Photo / Video with Camera'),
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
                Text('Upload Documents / Any File'),
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

  Future<void> _pickAndUploadMultipleMedia() async {
    AppPreferences.isPickerActive = true;
    try {
      final List<XFile> pickedFiles = await _imagePicker.pickMultipleMedia(
        imageQuality: 65,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (pickedFiles.isNotEmpty) {
        final localFiles = pickedFiles.map((x) => File(x.path)).toList();
        await _uploadBatchFiles(localFiles);
      }
    } catch (e) {
      debugPrint('[Picker] Multiple media pick error: $e');
      try {
        final List<PlatformFile> files = await FilePicker.pickFiles(
          type: FileType.media,
        );
        if (files.isNotEmpty) {
          final localFiles = files
              .map((f) => f.path)
              .whereType<String>()
              .map((p) => File(p))
              .toList();
          await _uploadBatchFiles(localFiles);
        }
      } catch (err) {
        AppToast.show(
          AppToast.userFriendlyMessage('Error selecting files: $err'),
          isError: true,
        );
      }
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _pickCameraMedia() async {
    AppPreferences.isPickerActive = true;
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 65,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (file != null) {
        await _uploadBatchFiles([File(file.path)]);
      }
    } catch (e) {
      AppToast.show(
        AppToast.userFriendlyMessage('Error taking photo: $e'),
        isError: true,
      );
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<void> _pickAndUploadDocument(FileType type) async {
    AppPreferences.isPickerActive = true;
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: type,
      );
      if (files.isNotEmpty) {
        final localFiles = files
            .map((f) => f.path)
            .whereType<String>()
            .map((p) => File(p))
            .toList();
        await _uploadBatchFiles(localFiles);
      }
    } catch (e) {
      AppToast.show(
        AppToast.userFriendlyMessage('Error selecting files: $e'),
        isError: true,
      );
    } finally {
      AppPreferences.isPickerActive = false;
    }
  }

  Future<File> _compressVaultFileIfNeeded(File originalFile) async {
    return await MediaCompressionService.instance.compressMedia(
      originalFile,
      isHd: false,
    );
  }

  Future<void> _uploadBatchFiles(List<File> files) async {
    if (files.isEmpty) return;

    setState(() {
      _isUploading = true;
      _uploadTotalCount = files.length;
      _uploadCurrentIndex = 0;
      _uploadBytesSent = 0;
      _uploadTotalBytes = 0;
    });

    final uploadedLocalFiles = <File>[];

    for (int i = 0; i < files.length; i++) {
      var file = files[i];
      if (!file.existsSync()) continue;

      final originalFileName = file.path.split(RegExp(r'[/\\]')).last;
      if (mounted) {
        setState(() {
          _uploadCurrentIndex = i + 1;
          _uploadingFileName = 'Compressing $originalFileName...';
          _uploadBytesSent = 0;
          _uploadTotalBytes = 1;
        });
      }

      // Compress media before uploading
      file = await _compressVaultFileIfNeeded(file);

      final fileName = file.path.split(RegExp(r'[/\\]')).last;
      if (mounted) {
        setState(() {
          _uploadingFileName = fileName;
        });
      }

      try {
        final uploadedItem = await ServerApiService.instance.uploadVaultFile(
          file,
          parentId: _currentParentId,
          folder: 'image',
          onProgress: (sent, total) {
            if (mounted && total > 0) {
              setState(() {
                _uploadBytesSent = sent;
                _uploadTotalBytes = total;
              });
            }
          },
        );

        if (uploadedItem != null) {
          uploadedLocalFiles.add(file);
        }
      } catch (e) {
        debugPrint('[Upload] Error uploading ${file.path}: $e');
      }
    }

    if (mounted) {
      setState(() => _isUploading = false);
      _handleRefresh();

      if (uploadedLocalFiles.isNotEmpty) {
        _promptDeleteLocalFiles(uploadedLocalFiles);
      }
    }
  }

  void _promptDeleteLocalFiles(List<File> files) {
    final count = files.length;
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Local Copy?'),
        content: Text(
          'Uploaded $count item${count > 1 ? 's' : ''} to Private Vault.\n\n'
          'Do you want to delete the local file${count > 1 ? 's' : ''} from your phone storage to save space and protect your privacy?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Local Copy'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              int deletedCount = 0;
              for (final f in files) {
                try {
                  if (await f.exists()) {
                    await f.delete();
                    deletedCount++;
                  }
                } catch (e) {
                  debugPrint('[DeleteLocal] Failed deleting ${f.path}: $e');
                }
              }
              if (deletedCount > 0) {
                AppToast.show('Deleted $deletedCount file(s) from phone storage.');
              }
            },
            child: const Text('Delete from Phone'),
          ),
        ],
      ),
    );
  }

  List<UploadItemModel> _getFilteredItems() {
    if (_searchQuery.trim().isEmpty) return _items;
    final q = _searchQuery.trim().toLowerCase();
    return _items.where((i) => i.fileName.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);

    return PopScope(
      canPop: _breadcrumbs.length <= 1,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onWillPop();
      },
      child: ShakePanicWrapper(
        child: VaultEdgePanelWrapper(
          child: Scaffold(
            backgroundColor: bgColor,
            body: Stack(
              children: [
                SafeArea(
                  child: Column(
                    children: [
                      PrivateFolderHeader(
                        isDark: isDark,
                        breadcrumbs: _breadcrumbs,
                        isGridView: _isGridView,
                        onToggleLayout: () => setState(() => _isGridView = !_isGridView),
                        searchController: _searchController,
                        onSearchChanged: (val) => setState(() => _searchQuery = val),
                        onBack: () {
                          if (!_onWillPop()) return;
                          Navigator.pop(context);
                        },
                        onCreateFolder: _showCreateFolderDialog,
                        onBreadcrumbTap: _onBreadcrumbTap,
                        onUpload: _showUploadOptions,
                      ),
                      Expanded(
                        child: RefreshIndicator.adaptive(
                          onRefresh: _handleRefresh,
                          child: _buildExplorerContent(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isUploading) _buildUploadProgressOverlay(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExplorerContent(bool isDark) {
    final filteredItems = _getFilteredItems();

    if (_isLoading && _items.isEmpty) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }

    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.exclamationmark_circle, color: CupertinoColors.systemRed, size: 48),
              const SizedBox(height: 12),
              Text(
                'Failed to load vault items',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              CupertinoButton.filled(
                onPressed: () => _fetchVaultData(page: 1, isRefresh: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (filteredItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.all(28.0),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.white.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.15)
                        : const Color(0xFFE5E5EA),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF007AFF).withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFAF52DE), Color(0xFF007AFF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFAF52DE).withOpacity(0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(
                        _searchQuery.isNotEmpty
                            ? CupertinoIcons.search
                            : CupertinoIcons.folder_fill_badge_plus,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'No Items Found'
                          : 'Vault Storage is Empty',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'No files matching "$_searchQuery" were found in this folder.'
                          : 'Store photos, videos, recordings, and files securely inside custom folders.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark
                            ? const Color(0xFFA0A0A5)
                            : const Color(0xFF6C6C70),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    if (_searchQuery.isEmpty) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _showCreateFolderDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.1)
                                      : const Color(0xFF007AFF).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF007AFF).withOpacity(0.3),
                                    width: 1.0,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      CupertinoIcons.folder_badge_plus,
                                      color: Color(0xFF007AFF),
                                      size: 16,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'New Folder',
                                      style: TextStyle(
                                        color: Color(0xFF007AFF),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: _showUploadOptions,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFAF52DE), Color(0xFF007AFF)],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFAF52DE).withOpacity(0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      CupertinoIcons.add,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Upload Files',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Separate folders and files for clean grouped display
    final folders = filteredItems.where((i) => i.isFolder).toList();
    final files = filteredItems.where((i) => !i.isFolder).toList();

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        // Subfolders Section Header
        if (folders.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'FOLDERS (${folders.length})',
                style: TextStyle(
                  color: isDark ? const Color(0xFFA0A0A5) : const Color(0xFF6C6C70),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _isGridView
                ? SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.3,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = folders[index];
                        return MediaGridItem(
                          item: item,
                          isSquareGrid: true,
                          onTap: () => _onFolderItemTap(item),
                          onRename: () => _renameItem(item),
                          onDelete: () => _deleteItem(item),
                        );
                      },
                      childCount: folders.length,
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = folders[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: MediaGridItem(
                            item: item,
                            isSquareGrid: false,
                            onTap: () => _onFolderItemTap(item),
                            onRename: () => _renameItem(item),
                            onDelete: () => _deleteItem(item),
                          ),
                        );
                      },
                      childCount: folders.length,
                    ),
                  ),
          ),
        ],

        // Files Section Header
        if (files.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, folders.isNotEmpty ? 20 : 12, 16, 8),
              child: Text(
                'FILES (${files.length})',
                style: TextStyle(
                  color: isDark ? const Color(0xFFA0A0A5) : const Color(0xFF6C6C70),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _isGridView
                ? SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.0,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = files[index];
                        return MediaGridItem(
                          item: item,
                          isSquareGrid: true,
                          onTap: () => _onFolderItemTap(item),
                          onRename: () => _renameItem(item),
                          onDelete: () => _deleteItem(item),
                        );
                      },
                      childCount: files.length,
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = files[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: MediaGridItem(
                            item: item,
                            isSquareGrid: false,
                            onTap: () => _onFolderItemTap(item),
                            onRename: () => _renameItem(item),
                            onDelete: () => _deleteItem(item),
                          ),
                        );
                      },
                      childCount: files.length,
                    ),
                  ),
          ),
        ],

        if (_isFetchingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CupertinoActivityIndicator(radius: 12),
              ),
            ),
          ),
        if (!_hasMore && _items.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'All $_total items loaded',
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildUploadProgressOverlay(bool isDark) {
    final progress = _uploadTotalBytes > 0
        ? (_uploadBytesSent / _uploadTotalBytes).clamp(0.0, 1.0)
        : 0.0;
    final percentage = (progress * 100).toInt();

    return Container(
      color: Colors.black.withOpacity(0.55),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1C1C1E).withOpacity(0.85)
                    : Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.2) : const Color(0xFFE5E5EA),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF007AFF).withOpacity(0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFAF52DE), Color(0xFF007AFF)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFAF52DE).withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: CupertinoActivityIndicator(
                        color: Colors.white,
                        radius: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Uploading to Vault',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'File $_uploadCurrentIndex of $_uploadTotalCount',
                    style: TextStyle(
                      color: isDark ? const Color(0xFFA0A0A5) : const Color(0xFF6C6C70),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _uploadingFileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: isDark
                              ? Colors.white.withOpacity(0.12)
                              : const Color(0xFFE5E5EA),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF007AFF),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _uploadTotalBytes > 0
                                ? '${_formatBytes(_uploadBytesSent)} / ${_formatBytes(_uploadTotalBytes)}'
                                : '',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFFA0A0A5)
                                  : const Color(0xFF6C6C70),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$percentage%',
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFFA0A0A5)
                                  : const Color(0xFF6C6C70),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

