# SWCompression（fork）脅威モデル（2026-11-15）

規約: `~/Developer/Claude/Conventions/security-audit-conventions.jp.md` v1.3 第1段。
対象 commit: `49306124d9df61fe6aa3359757e7df428f060c27`（`sy` ブランチの HEAD。`Sources/` と `Package.swift` は tag
`4.9.1-sy.12`＝`e3212c6b` と同一で、その後の commit は記録の文書だけ）。

自作コード（と扱うもの）: この repo は上流 [tsolomko/SWCompression](https://github.com/tsolomko/SWCompression) 4.9.1 の
**fork**。ライブラリ本体 `Sources/{Common,7-Zip,BZip2,Deflate,GZip,LZ4,LZMA,LZMA2,TAR,XZ,ZIP,Zlib}` の Swift 約 9,600 行の
うち、fork で足した・変えたのは 30 ファイル（+1,335／−124 行、`git diff --stat 56267f0e..HEAD -- Sources`）。
**上流から来たコードも、利用側のアプリにとっては取り込んだ自前のコードなので、全体を点検の対象にする**（上流の穴は
上流が直すのを待てない。利用側は `exact: "4.9.1-sy.N"` でこの fork に固定している）。
旧い記録: なし（規約以前のレビュー記録は無い）。ただし `sy.3`〜`sy.12` の堅牢化は、利用側のアプリの点検
（Arkheion 2026-10-30・Pinakeion 2026-10-31・Demion 2026-11-01）から来ている（`README.md` の "Differences from upstream"）。

## 1. どんなものか

- 圧縮（Deflate・BZip2・LZMA/LZMA2・LZ4）の展開と一部の圧縮、書庫（Zlib・GZip・XZ）、コンテナ（ZIP・TAR・7-Zip）の
  読み取りと一部の書き込みを行う **Swift のライブラリ**（SPM）。依存は `BitByteData` 2.1.0（`e1a5443b`、同じ作者の
  バイト／ビット読み取り器）。
- **入力はすべて `Data`（全体をメモリに持つ）**。出力も一括で `Data`／`[Entry]` を返す（`TarReader`・`TarWriter` だけは
  `FileHandle` で逐次）。**ライブラリはファイルを書かない・パスを解決しない**: エントリ名は文字列として返すだけで、
  どこに書くかは利用側が決める。ネットワーク・プロセス起動も無い。
- fork が足したもの（`README.md` "Differences from upstream" が正）:
  1. 7-Zip の BCJ 分岐フィルタ（`7-Zip/BranchFilters.swift`、x86・ARM・ARMT・ARM64・PPC・SPARC。XZ Utils からの移植）
  2. LZMA/LZMA2 を Apple の `Compression` へ通す高速経路（`Common/LZMAFraming.swift`。7z の生ストリームを `.xz`／`.lzma` の
     枠で包んで `compression_stream` に渡す）
  3. 復号の進捗通知（`Common/DecodeProgress.swift`、スレッドローカルの sink）
  4. 堅牢化（`sy.3`〜`sy.12`）: 範囲外アクセスの trap を throw に、出力の上限（内部の `limit`、公開の
     `BZip2.decompress(data:limit:)`・`GzipArchive.unarchive(archive:limit:)`・`XZArchive.unarchive(archive:limit:)`・
     `LZMA.decompress(data:limit:)`、`DecompressionLimitExceeded`）、`SevenZipContainer.folderUnpackSizes(container:)`、
     7z の coder・stream の数を 64 まで、符号化ヘッダの展開を 128 MiB まで
- `Sources/swcomp/` は上流の開発用の CLI（`Package.swift` で macOS のみ、ライブラリの product には入らない）。利用側は使わない。

### 利用側（影響の範囲）

4 アプリが `4.9.1-sy.12`（`e3212c6b`）に固定している（各 `Package.resolved`、2026-11-15 確認）: **Pinakeion・Arkheion・
Skopeion・Demion**。どのアプリがどの API を、どの入力（利用者が開いた書庫・自動で走るサムネイル作成 など）に使うかは
監査記録 `audit-20261115.md` §3 に表で残す。

## 2. 守るもの

1. **利用側のプロセスが落ちないこと**: Swift の trap（配列の範囲外・整数のあふれ・`precondition`・強制 unwrap）は
   `try?` で受けられず、利用側のアプリ（サムネイル作成のように利用者の操作なしに走るものを含む）ごと落ちる。
   **細工した書庫 1 つでアプリが起動のたびに落ちる**のを防ぐ。
2. **メモリと時間が際限なく使われないこと**: 展開比の大きい入力（zip bomb の類）、宣言サイズを信じた巨大な確保、
   出力の上限の抜け、終わらないループ。
3. **展開結果の正しさ**: 壊れた入力が、黙って別の中身（もっともらしいゴミ）を返さないこと（CRC の検査の抜け、
   高速経路の誤り）。利用側はこれを本物の中身として表示・変換・再圧縮する。
4. **エントリ名の扱いを利用側が正しくできること**: ライブラリは名前を加工せずに返す。`../`・絶対パス・NUL・
   symlink／hardlink の行き先・重複名を、**利用側が見分けられる形で**返すこと（勝手に変形して検査をすり抜けさせない）。
5. **公開 API の約束を守ること**: `limit:` を渡したら、それを超える出力を作る前に止まること。`info()` と `open()` が
   同じ解釈をすること（利用側は `info()` で検査してから `open()` を呼ぶ）。

## 3. 攻撃面（信用できない入力）

信用度: A＝インターネットの誰でも／B＝利用者が開いたもの／C＝同じ Mac の別プロセス／D＝利用者の設定・操作。
**全攻撃面が B**（利用者がダウンロードして開いた書庫・圧縮ファイル。作ったのは任意の他人なので、中身は A と同じく
完全に細工できる）。利用側のサムネイル作成・一覧の自動処理は、利用者がフォルダを開いただけで走る。

| ID | 攻撃面 | 入口のファイル | 信用度 | 想定する攻撃 | 第2段で見ること |
|---|---|---|---|---|---|
| S1 | Deflate・Zlib・GZip | `Deflate/*.swift`（展開）・`Zlib/*.swift`・`GZip/*.swift`・`Common/CodingTree/*`・`Common/CheckSums.swift`・`Common/Extensions.swift`・`Common/OutputLimit.swift` | B | 範囲外の距離・長さ、Huffman 表の細工、出力の上限の抜け（`limit:`）、multi-member gzip、ヘッダの拡張欄・名前・コメントの長さ、CRC・ISIZE の検査 | 全ての読み取りの境界、`limit` の効き方、整数のあふれ |
| S2 | BZip2 | `BZip2/*.swift`（展開側。圧縮は入力が利用者のデータなので見るだけ） | B | ブロックサイズ・RUNA/RUNB の連なり、BWT のポインタ、MTF、Huffman の表の数と長さ、`multiDecompress`、CRC | 同上 |
| S3 | LZ4 | `LZ4/*.swift` | B | フレーム・ブロックのサイズ、長さの延長（255 の連続）、オフセット、辞書・辞書 ID、`multiDecompress`、チェックサム | 同上 |
| S4 | LZMA・LZMA2・XZ と高速経路 | `LZMA/*.swift`・`LZMA2/*.swift`・`XZ/*.swift`・`Common/LZMAFraming.swift`・`Common/DecodeProgress.swift` | B | 辞書サイズ・properties、range decoder、LZMA2 のチャンクの状態遷移、XZ のブロック・インデックス・フィルタ・check、`splitUnarchive`、`Compression` へ渡す枠の作り方と上限の止め方、進捗の sink の再入 | 同上、高速経路と純 Swift 経路で結果・上限が食い違わないか |
| S5 | 7-Zip コンテナ | `7-Zip/*.swift`（`BranchFilters.swift`・`MsbBitReader+7z.swift` を含む） | B | ヘッダの数・サイズ・オフセット、符号化ヘッダ、folder の coder の鎖、substream、エントリの属性・名前・時刻、BCJ フィルタの境界、`info()`・`open()`・`folderUnpackSizes()` の食い違い、空のストリーム、暗号化 | 同上、`folderUnpackSizes` が実際の確保を本当に上から押さえるか |
| S6 | TAR コンテナ | `TAR/*.swift`（`TarReader`・`TarParser`・`TarContainer`・`TarHeader`・`TarExtendedHeader`・`TarEntryInfo`。`TarWriter`・`create` は出力側） | B | ヘッダのサイズ（8 進・base-256）、チェックサム、PAX・GNU longname/longlink の長さとくり返し、エントリ名・リンク先の組み立て、`TarReader` の逐次読み（`FileHandle`）、`info()` と `open()` の食い違い | 同上、名前の組み立て（prefix＋name、PAX `path`）の扱い |
| S7 | ZIP コンテナ | `ZIP/*.swift` | B | 中央ディレクトリ・ローカルヘッダの食い違い、ZIP64、エントリ数・サイズ・オフセット、拡張欄、名前の文字コード（CP437・UTF-8）、圧縮方式の分岐、data descriptor | 同上 |
| S8 | エントリ名とメタデータ（全コンテナ共通） | `Common/Container/*.swift`・各コンテナの `*EntryInfo.swift` | B | `../`・絶対パス・NUL・制御文字・Unicode の正規化・symlink／hardlink の行き先・重複名・権限ビット（setuid）。**ライブラリは書かないので、利用側への渡し方として見る** | 名前を変形していないか、利用側が判断に要る情報（種類・リンク先）が落ちていないか |
| S9 | 依存 `BitByteData` 2.1.0 | `.build/checkouts/BitByteData/Sources/*.swift` | B（S1〜S7 経由） | `ByteReader`／`BitReader` の範囲外の読み取りで trap するか（`precondition` か、配列の範囲外か） | 各読み取り関数の境界の振る舞い。ライブラリ側の呼び手がそれを前提に守っているか |
| S10 | 開発用の CLI と補助 | `Sources/swcomp/**`・`utils.py`・`azure-pipelines.yml` | D | `swcomp` の展開が書庫のパスをそのまま使う（`../`）、symlink をたどった書き込み | **利用側は使わない・配らない**。参考として見るだけ（指摘は「参考」に回す） |

## 4. 前提と対象外

- 自分専用。この fork は GitHub に remote（`origin`）を持つが、**配布はアプリに組み込んだ形だけ**。ライブラリとしての
  他人向けの配布は想定しない（上流には何も提案していない）。
- **全 repo 共通の受容は数えない**（規約 §8）: X1。この repo には `install.sh` も Releases も無く、関係しない。
- 物理的な接触、Apple ID・Mac の侵害、root 権限の攻撃者は対象外。
- **ライブラリは書き出しをしない**。展開先のパスの検査（zip slip）、ディスクの残量、書き込み先の symlink は**利用側の
  責任**として、各アプリの点検で見る。ここで見るのは、名前を利用側にどう渡すか（S8）まで。
- 出力の量の上限は、**利用側が `limit:`／`folderUnpackSizes()`／`info()` で決める**のが設計。上限を取らない旧 API
  （`GzipArchive.unarchive(archive:)` など）が無制限なのは上流の仕様で、それ自体は指摘にしない。指摘にするのは、
  上限を渡したのに効かない場合、上限を取る API が無いために利用側が守れない場合、上限より前に入力の大きさに見合わない
  確保・時間が起きる場合。
- 第三者の既知の穴（`BitByteData`・`SwiftCLI`）は[既知脆弱性の監視](../../../Conventions/vulnerability-watch-conventions.jp.md)の
  対象。ここでは S9 として、ライブラリが `BitByteData` をどう呼ぶかと、その読み取り器の境界の振る舞いだけを見る。
- 圧縮側（`compress`・`archive`・`create`・`TarWriter`）は入力が利用者自身のデータなので、穴の重さを下げて扱う
  （落ちる・壊れた出力を作る は記録する）。
- `Tests/`（上流の試験と、git submodule の `Tests/Test Files`）は対象外。生成物（`.build/`・`SWCompression.xcodeproj` の中身）も対象外。
