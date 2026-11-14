<p align="center"><img src="icon-1024.png" width="128" alt="Hark icon"></p>

# Hark

**Talk to Claude instead of Siri on iOS 10.** Hark is a voice assistant for iPhones and iPads stuck on iOS 10 (iPhone 5 / 5c and up). It listens, sends your question to Claude through the Anthropic API together with a snapshot of the device's status, and reads the answer aloud. Jailbroken? Add the **HarkSiri** tweak and holding the Home button opens Hark instead of Siri.

## What it does

- **Voice in, voice out**: on-device Speech framework recognition (iOS 10), Claude's answer spoken with the system voice in your language. Conversation mode keeps listening for follow-ups.
- **Knows your device**: every question carries the current time, battery level and charging state, Low Power Mode, network (Wi-Fi name or cellular type and carrier), free storage, RAM, uptime, brightness, volume and audio output, language, model and iOS version, and if you allow it, your location, the next events in your calendar and what's playing in the Music app. Ask "how much battery do I have?", "what's on today?" or "am I on Wi-Fi?".
- **Web search** for news, weather, prices and anything else current, with your approximate location.
- **Your choice of model**: Claude Opus 5.5 (default), Sonnet 5.5 (faster) or Haiku 5.5 (fastest and cheapest).
- **Type instead of talk** when you can't speak, copy any answer, start a new conversation anytime.
- **Your own instructions** ("call me Max, answer in Russian").

## Install

Grab the files from the [latest release](https://github.com/maxxponyata-sys/Hark/releases/latest).

| Device | Files | How |
|---|---|---|
| Jailbroken | `Hark-1.0.0-iphoneos-arm.deb` + `HarkSiri-1.0.0-iphoneos-arm.deb` | Install both with Filza or `dpkg -i`, then respring. Holding Home now opens Hark. |
| Not jailbroken | `Hark-1.0.0.ipa` | Sideload it with Sideloadly or a similar tool. Start it with "Hey Siri, open Hark" or from the Dock. |

Then open **Settings** in Hark, paste your Anthropic API key (create one at [console.anthropic.com](https://console.anthropic.com/settings/keys)) and allow the microphone and speech recognition.

## HarkSiri tweak

On iOS 10, SpringBoard sends the Siri button to `SBAssistantController` (`handleSiriButtonDownEventFromSource:activationEvent:`). HarkSiri takes that press and opens `hark://listen` instead. It leaves the press to Siri when:

- the device is locked (Siri still works on the lock screen),
- Hark isn't installed,
- Siri is already on screen,
- or it's turned off with `enabled = false` in `/var/mobile/Library/Preferences/app.hark.siri.plist`.

Keep Siri turned on in Settings → Siri, otherwise iOS doesn't send the button press at all. The tweak only hooks on iOS versions that have this selector, and does nothing elsewhere.

## Privacy and cost

Questions go straight from your device to `api.anthropic.com` with your key; there's no server in between. The device snapshot is attached to each question, so turn off location or calendar sharing if you don't want those sent. Requests are billed to your Anthropic account. The key is stored in the iOS keychain.

## Building

Plain Objective-C, built with [Theos](https://theos.dev) against the iOS 10.3 SDK (see the [Rewind](https://github.com/maxxponyata-sys/Rewind) README for the SDK notes about armv7).

```bash
export THEOS=~/theos
python3 tools/make_art.py
make package FINALPACKAGE=1              # Hark app (.deb)
(cd tweak && make package FINALPACKAGE=1)  # HarkSiri tweak
```

## Status

Version 1.0.0 builds cleanly for armv7 and arm64. **It hasn't been run on a real iOS 10 device yet**, and the tweak's Siri hook is based on the iOS 10 SpringBoard headers and other tweaks that use them. Please [open an issue](https://github.com/maxxponyata-sys/Hark/issues) with your device and iOS version if something doesn't work.

## Disclaimer

Hark is an unofficial app, not made or endorsed by Anthropic or Apple. "Siri" is a trademark of Apple Inc.

## License

[MIT](LICENSE)
