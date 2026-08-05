# プリセット音源の追加手順

## 音源ファイルの要件

- **CAF 形式**（PCM 16-bit / 44.1kHz / mono）
- **20〜40秒**（AlarmKit はファイルを最後まで再生してからループするため、20秒以上でループの継ぎ目が目立たない）
- **商用利用可**のライセンス（App Store 配布物に含まれるため）
- 標準アラーム音と差別化でき、不快でないもの

## 追加手順

### 1. CAF ファイルを配置

`CustomSoundAlarm/Resources/Sounds/` に `.caf` ファイルを置く。

```
CustomSoundAlarm/Resources/Sounds/PresetAlarm.caf  ← 既存（ジャズ）
CustomSoundAlarm/Resources/Sounds/PresetBell.caf   ← 新規例
```

### 2. presetDefinitions にエントリ追加

`CustomSoundAlarm/Services/SoundStore.swift` の `presetDefinitions` に1行追加:

```swift
static let presetDefinitions: [PresetRegistration.Definition] = [
    PresetRegistration.Definition(fileName: "PresetAlarm.caf", labelKey: "preset_jazz"),
    PresetRegistration.Definition(fileName: "PresetBell.caf", labelKey: "preset_bell"),  // ← 追加
]
```

### 3. ローカライズ文字列を追加

`CustomSoundAlarm/Resources/en.lproj/Localizable.strings`:

```
"preset_bell" = "Bell";
```

`CustomSoundAlarm/Resources/ja.lproj/Localizable.strings`:

```
"preset_bell" = "ベル";
```

### 4. ビルド確認

`xcodegen` は不要（Resources/Sounds は既存の source path に含まれる）。
通常のビルドで `.caf` がバンドルに含まれることを確認する:

```bash
# クリーンビルド後に確認
xcodebuild build -project CustomSoundAlarm.xcodeproj -scheme CustomSoundAlarm \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/dd-check
APP=$(find /tmp/dd-check -name "CustomSoundAlarm.app" -path "*Debug*" | head -1)
ls "$APP/PresetBell.caf"
```

## CAF 変換手順（MP3/WAV → CAF）

### afconvert（macOS 標準ツール）

```bash
afconvert -f caff -d LEI16@44100 -c 1 input.mp3 output.caf
```

- `-f caff`: CAF 形式
- `-d LEI16@44100`: PCM 16-bit Little Endian / 44.1kHz
- `-c 1`: モノラル

### 20〜40秒へのカット

```bash
# 先頭から30秒だけ取り出す（実用例）
afconvert -f caff -d LEI16@44100 -c 1 input.mp3 output.caf
# カットが必要な場合は ffmpeg が便利:
ffmpeg -i input.mp3 -t 30 -acodec pcm_s16le -ar 44100 -ac 1 output.wav
afconvert -f caff -d LEI16@44100 -c 1 output.wav output.caf
```

### 確認

```bash
afinfo output.caf
# File type ID:   caff
# Data format:   1 ch,  44100 Hz, 'lpcm' (0x0000000C) 16-bit little-endian signed integer
```
