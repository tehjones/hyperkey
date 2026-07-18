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

Open HyperKey and grant Accessibility access when macOS prompts you. You can then enable launch at login from the menu bar.

HyperKey remaps Caps Lock to F19 with `hidutil`. The mapping remains active after quitting the app and is cleared when macOS restarts or another mapping replaces it.

## License

[MIT](LICENSE)
