# Task Checklist - Unified Apple Files-Style Liquid Glass Private Vault

- `[x]` Task 1: Redesign `PrivateFolderPage` into Unified Apple Glass Explorer
  - [x] Remove category tabs (`Photos`, `Videos`, `Audio`, `Docs`) and category overview tiles
  - [x] Implement single, unified grid/list view for folders and files
  - [x] Implement liquid glass header bar with breadcrumbs (`Vault Drive > Subfolder`), search filter, "+ New Folder", and "+ Upload"
  - [x] Unified media & file picker with auto-compression (`imageQuality: 70`)
  - [x] Real-time upload progress card with live percentage (`Uploading 45%...`)
  - [x] Post-upload local phone storage deletion prompt
  - [x] Automatic Calculator lock on background/minimize & ShakePanicWrapper
- `[x]` Task 2: Refine Header & Component Styling (`private_folder_header.dart`, `media_grid_item.dart`)
  - [x] Update `PrivateFolderHeader` for unified layout with breadcrumb trail
  - [x] Ensure subfolders and files render cleanly in single grid/list view with context actions (Rename, Delete)
- `[x]` Task 3: Verification & Clean Build
  - [x] Run `flutter analyze`
  - [x] Verify zero compilation errors
