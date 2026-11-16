# Implementation Plan - Unified Apple Files-Style Liquid Glass Private Vault

Redesign the Private Vault into a unified, ultra-clean **Apple Files / Google Drive-style File Explorer**, eliminating confusing category tabs (`Photos`, `Videos`, `Audio`, `Docs`) and separate category tiles. Present a seamless, liquid glass folder and file storage system where users can create custom folders, navigate nested subfolders via breadcrumbs, upload media & files, rename/delete items, track upload percentage in real-time, and clean up local phone storage post-upload.

## User Review Required

> [!IMPORTANT]
> - **Removal of Category Tabs**: Eliminates the segmented tabs (`Photos`, `Videos`, `Audio`, `Docs`) and category overview tiles. Everything is displayed in a single, clean, unified vault drive view.
> - **Custom Folder Structure**: Users can create subfolders at root or inside any existing folder.
> - **Unified Liquid Glass Explorer**: Shows folders and files side-by-side with automatic thumbnails, breadcrumbs, search filter, and list/grid layout toggle.
> - **Media Picker & Compression**: Unified media selection with auto-compression (`imageQuality: 70`) for fast uploads.
> - **Post-Upload Local File Deletion**: Asks user if they want to delete local phone copies after uploading.
> - **Calculator Auto-Lock**: Minimizing, backgrounding, or shaking the phone locks back to `CalculatorPage`.

## Proposed Changes

### Presentation Layer (Private Vault Design Overhaul)

#### [MODIFY] [private_folder_page.dart](file:///Users/harshpatel/StudioProjects/securecalc/lib/src/features/private_folder/presentation/pages/private_folder_page.dart)
- Remove segmented control tabs (`Photos`, `Videos`, `Audio`, `Docs`).
- Convert into a unified **Apple Glass File Explorer**:
  - Top Liquid Glass Header with Vault Title, "+ New Folder", and "+ Upload" buttons.
  - Interactive Breadcrumb Bar (`Vault > Summer 2026 > Vacation`).
  - Search / Filter bar for quick item lookup.
  - Unified grid/list displaying folders and files together.
  - Dynamic folder navigation (`parentId` stack).
  - Floating Live Upload Percentage Progress Card (`Uploading 45%...`).
  - Post-Upload Local File Deletion prompt dialog.
  - Panic lock via `ShakePanicWrapper` and `VaultEdgePanelWrapper`.

#### [MODIFY] [private_folder_header.dart](file:///Users/harshpatel/StudioProjects/securecalc/lib/src/features/private_folder/presentation/widgets/private_folder_header.dart)
- Simplify header: Liquid Glass frosted background, clear breadcrumbs (`Vault > Subfolder`), "+ New Folder", and "+ Upload" action buttons.

#### [MODIFY] [media_grid_item.dart](file:///Users/harshpatel/StudioProjects/securecalc/lib/src/features/private_folder/presentation/widgets/media_grid_item.dart)
- Enhanced Apple Glass styling for both folder cards and file tiles (images with crisp thumbnail previews, videos with play indicators, audio waveforms, document badges).
- Context action sheet with Rename & Delete options.

#### [DELETE/REPLACE] [private_folder_overview.dart](file:///Users/harshpatel/StudioProjects/securecalc/lib/src/features/private_folder/presentation/widgets/private_folder_overview.dart)
- Replace with unified grid/list views directly inside `private_folder_page.dart`.

## Verification Plan

### Automated Tests
- Run `flutter analyze` to verify zero errors across the project.

### Manual Verification
- Verify clean, single-view vault layout without tab bars or category boxes.
- Test creating folders, opening subfolders, navigating breadcrumbs.
- Test uploading media with percentage progress indicator.
- Test post-upload local file deletion prompt.
- Verify panic auto-lock on minimize/backgrounding.
