# Provisioning Profile Configuration Required

## Issue

The MacPGP project build is failing due to missing App Groups capability in the provisioning profiles. This **CANNOT be fixed programmatically** and requires manual intervention in Xcode or the Apple Developer Portal.

## Error Messages

```
error: Provisioning profile "Mac Team Provisioning Profile: *" doesn't include the App Groups capability.
error: Provisioning profile "Mac Team Provisioning Profile: *" doesn't support the group.com.macpgp.shared App Group.
error: Provisioning profile "Mac Team Provisioning Profile: *" doesn't include the com.apple.security.application-groups entitlement.
```

**Affected Targets:**
- FinderSyncExtension (3 errors)
- QuickLookExtension (3 errors)
- ShareExtension (3 errors)
- ThumbnailExtension (3 errors)

**Total:** 12 provisioning profile errors

## Required Fix

You must configure App Groups in Xcode OR the Apple Developer Portal. Choose **Option A** (recommended) or **Option B**:

### Option A: Xcode Automatic Signing (Recommended - Easiest)

1. Open `MacPGP/MacPGP.xcodeproj` in Xcode
2. For **each target** (MacPGP, FinderSyncExtension, QuickLookExtension, ShareExtension, ThumbnailExtension):
   - Select the target in the project navigator
   - Go to the **"Signing & Capabilities"** tab
   - Check **"Automatically manage signing"**
   - Select your development team from the dropdown
   - Xcode will automatically create/update provisioning profiles with the App Groups capability

3. Build the project to verify: `⌘ + B` or Product → Build

### Option B: Manual Provisioning Profile Configuration

If you prefer manual code signing:

#### Step 1: Add App Groups Capability in Xcode

1. Open `MacPGP/MacPGP.xcodeproj` in Xcode
2. For each target (MacPGP, FinderSyncExtension, QuickLookExtension, ShareExtension, ThumbnailExtension):
   - Select the target
   - Go to "Signing & Capabilities" tab
   - Click the **"+ Capability"** button
   - Select **"App Groups"**
   - Check the box for **"group.com.macpgp.shared"**

#### Step 2: Configure in Apple Developer Portal

1. Go to [Apple Developer Portal](https://developer.apple.com)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Click on **Identifiers**
4. For each App ID:
   - `com.macpgp` (MacPGP)
   - `com.macpgp.FinderSyncExtension`
   - `com.macpgp.QuickLookExtension`
   - `com.macpgp.ShareExtension`
   - `com.macpgp.ThumbnailExtension`

   Do the following:
   - Click the App ID
   - Enable the **"App Groups"** capability
   - Configure it to use **"group.com.macpgp.shared"**
   - Click **Save**

5. Go to **Profiles**
6. For each provisioning profile used by the targets:
   - Click **Edit** or regenerate the profile
   - Download the updated profile
   - Drag it to Xcode or use Xcode → Preferences → Accounts → Download Manual Profiles

#### Step 3: Rebuild

```bash
xcodebuild -project MacPGP/MacPGP.xcodeproj -scheme MacPGP -configuration Debug build
```

Expected output: **`** BUILD SUCCEEDED **`**

## Verification

After configuring App Groups, verify the build succeeds from the repository root:

```bash
xcodebuild -project MacPGP/MacPGP.xcodeproj -scheme MacPGP -configuration Debug build 2>&1 | grep -E "BUILD|error:"
```

**Expected:** No provisioning profile errors, and the last line shows `** BUILD SUCCEEDED **`

## Remaining Warnings (Non-Critical)

After fixing provisioning profiles, you may still see Info.plist warnings:
```
warning: The Copy Bundle Resources build phase contains this target's Info.plist file...
```

**These warnings are harmless and do not prevent the build from succeeding.** They occur because Xcode's File System Synchronized Groups automatically include Info.plist files in resources. This is a cosmetic issue that does not affect functionality.

To eliminate these warnings (optional):
- Open the project in Xcode
- For each target, go to Build Phases → Copy Bundle Resources
- Find and remove the Info.plist entry (if present)
- This requires Xcode GUI as it's not easily scriptable with the modern project format
