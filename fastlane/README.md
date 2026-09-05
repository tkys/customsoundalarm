fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

メタデータのみアップロード（スクリーンショットなし）

### ios upload_all

```sh
[bundle exec] fastlane ios upload_all
```

メタデータ + スクリーンショットをアップロード

### ios release

```sh
[bundle exec] fastlane ios release
```

リリースビルドを作成し App Store Connect にアップロード＆審査提出（v1.1.0）

### ios submit_only

```sh
[bundle exec] fastlane ios submit_only
```

アップロード済みビルドを（処理完了後に）審査提出する（署名不要・API のみ）

### ios bump

```sh
[bundle exec] fastlane ios bump
```

ビルド番号をインクリメント

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
