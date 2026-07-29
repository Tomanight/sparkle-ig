# SPKSideloadFix

Sparkle-local sideload app-group/keychain fix library.

This is derived from [`asdfzxcvbn/zxPluginsInject`](https://github.com/asdfzxcvbn/zxPluginsInject),
which is itself a rewrite of choco's original patch. It also vendors Facebook's
[`fishhook`](https://github.com/facebook/fishhook) for C symbol rebinding.

Compared with upstream `zxPluginsInject`, this variant changes app-group
container handling so `NSUserDefaults` uses the same redirected container policy
as `NSFileManager` in app-extension processes:

- retry app-group lookup until `LSBundleProxy` returns a usable group URL
- fall back to a Documents-backed group path when no app-group URL is available
- create redirected suite container directories before passing them to defaults
- keep main-app `NSUserDefaults` writes on their original container, so
  Instagram's cold-launch UI dismissal flags persist normally, while also
  mirroring app-group suites into the shared container the extensions read
  (`GroupDefaultsMirror.xm`)

The mirror exists because the notification extension boots from its app-group
defaults. With the extension redirected to the shared container but the main app
writing elsewhere, it found an empty plist, could not load
`FBMobileConfigStartupConfigs`, and stalled until iOS killed it:

    Extension will be killed because it used its runtime in starting up
    Did not mutate content for notification request, will deliver original
    content; runtime: 30.013551

That produced empty lock-screen previews (content never mutated) and duplicate
banners (Instagram's own notification dedupe, which runs in the extension, never
executed). Mirrored writes always call through to the original container first,
so the mirror is additive and nothing that already worked changes.

It also normalizes Keychain access groups for sideloaded signatures. The four
intercepted `SecItem` operations resolve a usable group from a sentinel Keychain
item first and fall back to runtime entitlements. Existing access-group values
in add/query/delete dictionaries are replaced, and missing values are injected.
For `SecItemUpdate`, the query is normalized the same way while the separate
attributes-to-update dictionary is changed only when it already contains an
access group, avoiding an unintended item migration.

Keychain diagnostics report only the operation, result status, timing, and
whether a group was found/replaced/injected. Access-group strings, Keychain
values, cookies, and credentials are never logged.

For duplicate-app sideloads, main-bundle runtime queries are normalized to
Instagram's original `com.burbn.instagram` identifier through both
`bundleIdentifier` and `objectForInfoDictionaryKey:`. The packaged identifier
is not changed, and non-main bundles keep their actual identities. This matches
Instagram's original runtime namespace for code that derives persisted-state
identifiers while still allowing a distinct identifier at install time.

Build with:

```sh
make -C modules/SPKSideloadFix DEBUG=0 FINALPACKAGE=1
```

`build.sh ipa --patch` builds this dylib and passes it to `ipapatch --dylib`
automatically.
