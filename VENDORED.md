# この fork の記録

規約: [`vendored-source-conventions.jp.md` §6.2.4](../Conventions/vendored-source-conventions.jp.md)。
機械可読な宣言は同ディレクトリの `vendored.json`。

**このリポジトリは取り込み (vendoring) ではなく fork。** リポジトリ全体が
[tsolomko/SWCompression](https://github.com/tsolomko/SWCompression) のクローンで、
上流とのズレは SHA-256 マニフェストではなく **git の merge-base** が追う。

## 1. なぜ分岐したか

7-Zip は入力が機械語に見えると **BCJ 分岐フィルタ**を自動適用するが、上流はそれを
1 つも実装しておらず `compressionNotSupported` で落ちる。**実行ファイルを含む
`.7z` / `.cb7` が一切開けない** —— 珍しい書庫ではなく、ごく普通に出てくるもの。

上流に投げて待つ選択肢もあったが、Pinakeion / Skopeion の利用者にはその間ずっと
「開けない書庫」が残る。採用されれば fork を畳んで上流 URL に戻す。
**ただし上流にはまだ何も提案していない**（2026-11-01 確認。PR も issue も無い）。
以前の記述「提案済み」は誤りだった。

**差分の詳細（何を変え、何を意図的に実装しなかったか）と版ごとの一覧は
[README.md の "Differences from upstream"](README.md#differences-from-upstream) が正。**
ここに再掲すると二重管理になる。要約すると 4 系統:

1. **7-Zip BCJ 分岐フィルタ**（正しさ）— XZ Utils の `simple/*.c`（public domain）からの
   移植。デコードのみ。BCJ2 / IA64 / RISC-V は意図的に未実装。
2. **LZMA/LZMA2 を Apple の `Compression` へ通す高速経路**（速度）— 非 Apple
   プラットフォームでは `#if canImport(Compression)` で上流どおりの純 Swift 経路に落ちる。
3. **復号の進捗通知** — 高速経路とチャンクループの**両方**で tick する
   （[7z 規約 §6.1](../Conventions/seven-zip-conventions.jp.md)）。
4. **デコーダの堅牢化**（安全）— `sy.3` 以降。壊れた入力での trap と、際限のない出力を
   投げられるエラーに変える。回帰テストはこの repo ではなく利用側のアプリにある。

## 2. 分岐点

| | |
|---|---|
| 上流 | `tsolomko/SWCompression`（`upstream` remote） |
| 分岐した版 | **4.9.1**（`03a68e67` — `Merge branch 'hotfix-4.9.1'`） |
| merge-base | `56267f0e14c582f991ee3cc725fbe03b09ac5e3a` |
| ライセンス | MIT（上流のまま。`LICENSE` を消さない） |
| 配布 | SPM。利用側は `exact: "4.9.1-sy.N"` で固定する |

## 3. 上流との距離（2026-11-01 実測、`4.9.1-sy.12` の時点）

```
git rev-list --count upstream/develop..HEAD   # 20 — こちらの独自コミット
git rev-list --count HEAD..upstream/develop   # 54 — 上流だけにあるコミット（全件読了）
```

**この数は横断ランナーが毎回 git に聞いて表示する**ので、ここに書いた値がずれても
実体は分かる —— 書いてあるのは「いつ、何件だったか」という記録の方。

**54 は「遅れている」であって「壊れている」ではない。** 上流の develop には
4.9.1 以降の変更が積まれているが、この fork が出荷しているのは 4.9.1 系の挙動 +
README の差分で、利用側 (`Package.resolved`) もその版を `exact` で固定している。
54 件の中身は `vendored.json` の `review` に記録がある（security fix は無い）。
**追随は判断であって自動ではない**（規約 §0「検知は自動、版上げの適用は人間」）。

## 4. 更新手順

1. `git fetch upstream`
2. `git log --oneline HEAD..upstream/develop` を**読む**。セキュリティ修正か、
   7-Zip / LZMA まわりの変更が入っているかを見る。
3. 取り込むなら `git merge upstream/develop`。BCJ の呼び出し箇所
   (`7zFolder.swift`) は上流も触る場所なので、**衝突は起きる前提**で読む。
4. `swift test` を通す。加えて **BCJ 検体を `7zz` とバイト比較**する
   （Pinakeion 側の受け入れ条件。バイト数一致だけで正しいと判断しない）。
5. 新しい tag を打つ（`4.9.1-sy.N` → 上流版が上がるなら `<新版>-sy.1`）。
6. `vendored.json` の `merge_base` / `review` を**手で**更新する。
   機械的に上げると「意図した版上げ」と「事故」の区別が付かなくなる。
7. 利用側（Pinakeion / Skopeion / Arkheion / Demion）の `Package.swift` / `project.yml` の
   `exact` を上げ、各 README の記述を合わせる。

## 5. 利用しているアプリ

各アプリの `Package.swift` と `Package.resolved` が正。2026-11-01 時点の記録:

| アプリ | 固定している版 | 備考 |
|---|---|---|
| Pinakeion | `4.9.1-sy.11` | |
| Arkheion | `4.9.1-sy.10` | |
| Skopeion | `4.9.1-sy.9` | |
| Demion | `4.9.1-sy.9` | branch `SY/silly-mendel-aeb8a1` は `sy.12`（main に未 merge） |

新しい版の穴は、その版より古いアプリに残る。

**CVE が上流に出たときの追随先は上流ではなくこの fork。** 利用側の README は
そう書いてある —— 上流の版だけ見ていると、追随したつもりで何も入っていない状態になる。
