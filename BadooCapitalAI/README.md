# BadooCapitalAI

Badoo iOS jailbreak tweak (Dopamine 17.03 / ElleKit) that connects Badoo conversations
to your Capital AI chatbot for fully automated, human-looking replies.

---

## Architecture

```
Badoo (conversation list reloads)
  └─ BDChatConversationListViewController hook
       └─ ConvoQueue  (online-first priority sort)
            └─ CapitalAPI  → POST /generateResponse
                 └─ BDChatConversationViewController hook
                      └─ HapticTyper  (char-by-char, jitter, 4% typo-then-backspace)
                           └─ tap Send
```

---

## Features

| Feature | Detail |
|---|---|
| Auto-open conversations | Taps into the list, navigates per-convo, pops back |
| Online-first priority | ConvoQueue sorts online users to the top |
| Recency tiebreak | Among offline, most-recently-active goes first |
| Human typing simulation | 60–140 ms/char gaussian jitter, random typos |
| Haptic keystroke feedback | CoreHaptics light tap on each char (device-only) |
| Multi-bubble delivery | Sends each `content[]` item in sequence with inter-bubble pause |
| Media support | Downloads image/video from Capital CDN → hands to Badoo share |
| Undetected timing | Think-delay = 1.5–4 s base + word-length bonus |
| Settings bundle | Enable toggle + licenseKey / modelId / presetId in Settings.app |

---

## Build

### Prerequisites

```bash
brew install ldid dpkg
export THEOS=~/theos        # https://theos.dev/docs/installation
```

### Compile

```bash
cd BadooCapitalAI
make package FINALPACKAGE=1
# .deb appears in packages/
```

### Install (over SSH from Dopamine device)

```bash
scp packages/*.deb mobile@<device-ip>:/tmp/
ssh mobile@<device-ip> "sudo dpkg -i /tmp/*.deb && uicache -a"
```

---

## Class names — when they break

Badoo obfuscates selectively. After a major update, re-dump:

```bash
# On device (needs class-dump-z in PATH)
class-dump -H /private/var/containers/Bundle/Application/*/Badoo.app/Badoo \
  -o ~/Desktop/BadooDump/

# Search for the real names:
grep -r "ConversationList\|ChatViewController\|MessageModel" ~/Desktop/BadooDump/
```

Then update the `%hook` target names in `Tweak.x`.

Key hooks to verify:
- `BDChatConversationListViewController` → the inbox list VC
- `BDChatConversationViewController`     → open chat VC
- `dataSource.conversations`             → the array of convo models
- `userId` / `conversationId`            → contact identifier key
- `isOnline`                             → online status bool
- `messages`                             → message array on the convo model
- `isOwn`                                → whether WE sent the message
- `sendMessage:` / `sendTextMessage:`    → internal send selector

---

## Configuration

Edit via **Settings.app → BadooCapitalAI** (PreferenceLoader):

| Key | Description |
|---|---|
| `enabled` | Master on/off toggle |
| `licenseKey` | Capital AI license key |
| `modelId` | Capital AI model ID (default: 43) |
| `presetId` | Capital AI preset ID (default: 88) |

Plist lives at:
`/var/mobile/Library/Preferences/com.jb.badoocapitalai.plist`

---

## Undetected behavior notes

- **Typing speed**: gaussian-jittered 54–126 ms/char average — human WPM range
- **Think delay**: 1.5–4 s before first character + word-length bonus
- **Typos**: 4% per character → type wrong char → 120 ms → backspace → correct char
- **Inter-bubble pause**: 0.8–1.6 s between multi-part replies
- **No simultaneous requests**: ConvoQueue processes one conversation at a time
- **Online filter**: skips conversations where WE sent last (no unanswered messages)

---

## Skipped (shortcut: add when needed)

- Preferenceloader bundle not auto-generated — manually paste Root.plist XML from `PreferenceLoader.m`
- accountId hardcoded as `"badoo_account"` — swap for actual Badoo user identifier
- Media send path uses `attachMediaAtURL:` selector guess — verify with class-dump
- No retry logic beyond 3 s back-off on API error
- No conversation age cutoff (`conversationCreatedAt` not passed) — add from convo model's `createdAt`
