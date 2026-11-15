# SWCompression（fork）機械検査（2026-11-15）

規約: `security-audit-conventions.jp.md` v1.3 第1段。対象 commit: `49306124d9df61fe6aa3359757e7df428f060c27`
（`Sources/` は tag `4.9.1-sy.12`＝`e3212c6b` と同一）。

## 結果のまとめ

| 道具 | 対象 | 結果 | 判定 |
|---|---|---|---|
| shellcheck | — | 対象なし | `git ls-files '*.sh'` が 0 件 |
| bandit 1.9.4（`-ll`） | `utils.py`（上流の開発補助） | 高 1 件（B602）・低 2 件 | 対象外の参考（下）。ライブラリにも利用側にも入らない |
| semgrep（`--metrics=off`・`p/default`・`p/c`・`p/secrets`・`p/swift`、329 規則・138 ファイル） | `Sources/`（swcomp を含む）・`utils.py`・`azure-pipelines.yml`・`Package.swift` | 1 件（`utils.py:14` の `shell=True`） | 上と同じもの。Swift の自作コードは 0 件。Swift に効く規則はわずかで、Swift の検査としてはほぼ効かない |
| clang static analyzer | — | 対象なし | C/C++/ObjC が無い |
| 秘密情報（`git log --all -p` を鍵の正規表現で検索: AWS・秘密鍵・GitHub・Slack・OpenAI/Anthropic・Google の鍵、`api_key=`・`password=`・`secret=`・`token=` の代入） | 全履歴 2,638 commit（`--all`、上流の履歴を含む） | 0 件 | — |
| Swift のコンパイラの警告 | ライブラリの Swift 全部（`Sources/` から `swcomp/` を除く） | **0 件** | 下の「Swift の警告」 |

## 個別の判定

| 道具 | 場所 | 内容 | 判定 |
|---|---|---|---|
| bandit B602・semgrep `subprocess-shell-true` | `utils.py:14` | `subprocess.run(cmd, shell=True)` | 対象外の参考。上流の CI 補助（`ci script-macos`）で、`xcodebuild -version` と `xcodebuild … -destination 'platform=iOS Simulator,name=<IOS_SIMULATOR>'` を shell に渡す。値は CI の環境変数（`azure-pipelines.yml` の固定値）で、外からの入力は入らない。fork では使っていない |
| bandit（低 2 件） | `utils.py:5`（`import subprocess`）ほか | 情報 | 同上 |

## Swift の警告

規約は「Swift に良い SAST が無いので、コンパイラの警告 0 を確かめ、第2段で読む」とする。ビルドはしない（点検の指示）ので、
型検査だけを行った（成果物はスクラッチパッドの依存のモジュール定義だけで、repo の `.build/` には触れていない）:

```
# 依存 BitByteData 2.1.0（.build/checkouts の写し、e1a5443b）のモジュール定義をスクラッチに作る
xcrun swiftc -emit-module -module-name BitByteData -parse-as-library -swift-version 5 \
  -target arm64-apple-macos14.0 -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -emit-module-path $SCRATCH/mod/BitByteData.swiftmodule .build/checkouts/BitByteData/Sources/*.swift
# ライブラリ本体を型検査
xcrun swiftc -typecheck -module-name SWCompression -parse-as-library -swift-version 5 \
  -target arm64-apple-macos14.0 -sdk "$(xcrun --show-sdk-path --sdk macosx)" -I $SCRATCH/mod \
  $(git ls-files 'Sources/*.swift' | grep -v '^Sources/swcomp/')
```

Apple Swift 6.4.2 で **警告 0・エラー 0**。`Package.swift` は `swiftLanguageVersions: [.v5]` なので、Swift 6 の strict
concurrency の検査は効いていない（`DecodeProgress` のスレッドローカルは第2段で読んだ）。

## 依存

| 依存 | 版 | 使う所 | 備考 |
|---|---|---|---|
| BitByteData | 2.1.0（`e1a5443be67daf0833cbb5f4fa3a06a265ca3105`） | ライブラリ本体（バイト・ビットの読み取り） | 同じ作者。既知の advisory は監視の対象（`security-assessments.json` の gaps）。境界の振る舞いは第2段 S9 で読んだ |
| SwiftCLI | 6.0.3 | `swcomp`（開発用 CLI）だけ | ライブラリの product に入らない |
