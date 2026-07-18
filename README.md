# HyperKey

HyperKey is a minimal macOS menu bar app that turns Caps Lock into a dual-purpose key:

- Hold Caps Lock to use it as Hyper (Command + Shift + Control + Option).
- Tap Caps Lock to send F19.
- Use Hyper + H/J/K/L as arrow keys.

## Requirements

- macOS 13 or later
- Accessibility permission

## Build

```sh
./bundle.sh
cp -R HyperKey.app /Applications/
open /Applications/HyperKey.app
```

By default, the bundle is signed ad hoc, so macOS may ask for Accessibility
permission again after a changed build. To preserve the permission, sign with a
stable identity:

```sh
HYPERKEY_SIGNING_IDENTITY="Apple Development: Your Name" ./bundle.sh
```

Open HyperKey and grant Accessibility access when macOS prompts you. You can then enable launch at login from the menu bar.

HyperKey remaps Caps Lock to F19 with `hidutil` while it is active. When HyperKey quits, it restores the Caps Lock mapping that was in place before it started.

## License

[MIT](LICENSE)
