---
title: "macOSで手軽にSandbox環境を構築できるApple Seatbeltの実践ガイド"
emoji: "🔒"
type: "tech"
topics: ["mac", "security", "ai", "claudeCode", "appleSeatbelt"]
published: true
---

# TL;DR

- **Apple Seatbelt**は、macOSに組み込まれたサンドボックス機構です。ファイルアクセスやネットワーク通信を細かく制限できます。
- LLMベースのAI Agentツールは広範囲にファイルシステムへアクセスできるため、セキュリティ上の懸念があります。**Apple Seatbelt**はその有効な対策となります。
- DevContainerは完全な隔離環境を提供しますが、起動に数秒〜数十秒かかります。**Apple Seatbelt**は起動オーバーヘッドがほぼゼロで、カーネルレベルの保護を実現します。
- 本記事では、Claude Codeを例に**Apple Seatbelt**の実践的な使い方を紹介します。

# 想定読者

- macOSでClaude CodeやCursor等のAI Agentツールを使用している開発者
- AI Agentの実行権限を制限し、セキュリティを強化したい方
- macOSのサンドボックス機構に興味がある方

# Apple Seatbeltとは

Apple Seatbeltは、macOSに標準搭載されているサンドボックス機構です。アプリケーションやプロセスに対して、ファイルシステム、ネットワーク、プロセス間通信などのリソースアクセスを細かく制限できます。

参考: [Sandbox operations (非公式逆引き)](https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf)

Apple Seatbeltは、macOSのカーネルレベルで動作する強制アクセス制御（MAC: Mandatory Access Control）機構です。プロセスに対して以下の流れでアクセス制御を行います。

1. **プロファイルの読み込み**: `sandbox-exec`コマンドで、プロセス起動時にセキュリティプロファイルを適用
2. **カーネルによる監視**: プロセスがシステムコールを実行するたびに、カーネルがプロファイルと照合
3. **許可/拒否の判定**: プロファイルのルールに基づいて、操作を許可または拒否

プロファイルは **SBPL（Sandbox Profile Language）** という専用言語で記述します。SBPLはSchemeライクな[S式](https://ja.wikipedia.org/wiki/S%E5%BC%8F)による宣言的な設定形式です。「このディレクトリ以下への書き込みは許可するが、.envファイルの読み込みは拒否する」といった細かいルールを柔軟に定義できます。

ターミナルから以下のように使用します：

```bash
# sandbox-execコマンドでプロファイルを適用してプログラムを実行
sandbox-exec -f profile.sb プログラム名
```

`profile.sb`はSBPLで記述されたプロファイルファイルです。この仕組みにより、既存のアプリケーションを変更することなく、実行時にサンドボックス環境を構築できます。

- **軽量**: コンテナやVMと異なり、ほぼオーバーヘッドなしで動作
- **柔軟な制御**: SBPLによる細かい権限設定が可能（詳細は後述）
- **システム統合**: macOSに標準搭載されており、`sandbox-exec`コマンドで即座に利用可能
- **既存プログラムへの適用**: プログラム自体を変更せず、実行時にサンドボックス化することが可能

しかしながら、Apple Seatbeltは公式にドキュメントを公開されておらず、非推奨とされています。一方で実際には多くのアプリケーションやツールで使用されています。

**採用事例**
- **iOS/macOSアプリ**: すべてのiOSアプリはサンドボックス内で実行される（ただし、現在は[App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)が推奨される）
- **Chromium**: macOS版ChromiumでApple Seatbeltを適用（[sandbox/mac ディレクトリ](https://github.com/chromium/chromium/tree/main/sandbox/mac)、Sandbox Profile: [`renderer.sb`](https://chromium.googlesource.com/chromium/src/+/770eff8/sandbox/policy/mac/renderer.sb)、[`gpu.sb`](https://chromium.googlesource.com/chromium/src/+/770eff8/sandbox/policy/mac/gpu.sb)）
- **AI Agentツール**:
  - **Claude Code**: macOSでApple Seatbeltを使用してファイルシステムとネットワークを隔離（[公式ドキュメント](https://docs.claude.com/en/docs/claude-code/sandboxing)、[オープンソース実装](https://github.com/anthropic-experimental/sandbox-runtime)）
  - **Gemini CLI**: macOS向けSBPLファイルを公開（[`sandbox-macos-permissive-open.sb`](https://github.com/google-gemini/gemini-cli/blob/1ef34261e09a6b28177c2a46384b19cfa0b5bea0/packages/cli/src/utils/sandbox-macos-permissive-open.sb)）

:::message
**補足:** Appleはアプリ配布や製品用途ではエンタイトルメントベースのApp Sandboxを推奨しています（[Apple Developer: App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)）。一方、`sandbox-exec`による動的プロファイルはドキュメントが限られており、主に開発・検証やプロセス単位の一時的な制限に適した手法です。
:::

# SBPL（Sandbox Profile Language）

SBPLはSchemeライクな[S式](https://ja.wikipedia.org/wiki/S%E5%BC%8F)で許可・拒否ルールを定義する専門言語です。

## 基本構文

SBPLの基本構造は非常にシンプルです。`version`宣言の後、`allow`と`deny`を組み合わせてルールを定義します。

```scheme:profile.sb
(version 1)

;; デフォルトで全て許可
(allow default)

;; 特定の操作を拒否
(deny file-write*)

;; 条件付きで許可
(allow file-write*
    (subpath "/tmp")
)
```

**ルール評価の優先順位**
1. より具体的なルールが優先されます
2. `deny`は`allow`よりも優先されます

## 主要な操作タイプ

SBPLでは、システムコールレベルでの細かい操作タイプを指定できます。

### ファイルシステム操作

| 操作 | 説明 |
|------|------|
| `file-read*` | ファイル読み込み全般（メタデータ含む） |
| `file-read-data` | ファイルデータの読み込みのみ |
| `file-read-metadata` | ファイルのメタデータ（stat等）の読み込み |
| `file-write*` | ファイル書き込み全般（作成・削除含む） |
| `file-write-data` | 既存ファイルへのデータ書き込み |
| `file-write-create` | 新規ファイルの作成 |
| `file-write-unlink` | ファイルの削除 |
| `file-write-setattr` | ファイル属性の変更（chmod等） |

### ネットワーク操作

| 操作 | 説明 |
|------|------|
| `network*` | すべてのネットワーク操作 |
| `network-outbound` | 外部への通信（クライアントとして接続） |
| `network-inbound` | 外部からの通信受信（サーバーとして待ち受け） |
| `network-bind` | ポートへのバインド |

### プロセス・IPC操作

| 操作 | 説明 |
|------|------|
| `process-exec` | 新しいプロセスの実行 |
| `process-fork` | プロセスのfork |
| `signal` | シグナルの送信 |
| `ipc-posix-shm` | POSIX共有メモリ |
| `ipc-posix-sem` | POSIXセマフォ |
| `mach-lookup` | Machポートのルックアップ（macOS特有） |
| `sysctl-read` | システム情報の読み込み |
| `sysctl-write` | システム設定の変更 |

### その他

| 操作 | 説明 |
|------|------|
| `default` | すべての操作（デフォルトポリシー設定に使用） |
| `system-socket` | システムソケットへのアクセス |
| `iokit-open` | IOKitデバイスのオープン（ハードウェアアクセス） |

## 条件指定の方法（フィルター）

操作に対して、どのリソースに適用するかを条件で絞り込みます。

### パス指定フィルター

```scheme
;; 完全一致
(literal "/exact/path/to/file")

;; サブディレクトリを含む（末尾スラッシュ推奨）
(subpath "/directory/")

;; 正規表現（POSIX正規表現）
(regex #"\.env$")                    ; .envで終わるファイル
(regex #"^/private/tmp/")            ; /private/tmp/で始まるパス
(regex #"/\.[^/]*$")                 ; ドットファイル（.gitignore等）
```

### ネットワーク指定フィルター

```scheme
;; リモートホスト指定
(remote ip "192.168.1.1:443")        ; 特定のIPとポート
(remote ip "192.168.1.0/24:*")       ; サブネット全体
(remote tcp "*:80")                   ; すべてのホストのポート80

;; ローカルポート指定
(local tcp "*:8080")                  ; ローカルの8080番ポートへのバインド
```

### 論理演算子

複数の条件を組み合わせることができます。

```scheme
;; require-all: すべての条件を満たす（AND）
(deny file-read*
    (require-all
        (subpath "/Users/")
        (regex #"\.env$")
    )
)

;; require-any: いずれかの条件を満たす（OR）
(deny file-write*
    (require-any
        (literal "/etc/hosts")
        (literal "/etc/passwd")
        (subpath "/System/")
    )
)

;; require-not: 条件を満たさない（NOT）
(allow file-read*
    (require-not
        (regex #"\.env.*$")
    )
)
```

### パラメータと文字列操作

実行時にパラメータを渡すことで、柔軟なプロファイルを作成できます。

```scheme
;; パラメータの使用
(subpath (param "TARGET_DIR"))

;; 文字列結合
(literal (string-append (param "HOME") "/.ssh/id_rsa"))
(regex (string-append "^" (param "HOME") "/Documents/"))

;; 複雑な例：ホームディレクトリ配下の特定パターンを拒否
(deny file-read*
    (regex
        (string-append
            "^"
            (param "HOME_DIR")
            "/\\.aws/credentials$"
        )
    )
)
```

## 実用的なパターン例

### 特定の拡張子を持つファイルを保護

```scheme
;; シークレットファイルの読み込みを拒否
(deny file-read*
    (require-any
        (regex #"\.env$")
        (regex #"\.env\..*$")
        (regex #"secrets\.json$")
        (regex #"\.pem$")
    )
)
```

### プロジェクトディレクトリ以外への書き込みを制限

```scheme
;; デフォルトで書き込み拒否
(deny file-write*)

;; プロジェクトディレクトリのみ許可（システムファイルは除外）
(allow file-write*
    (require-all
        (subpath (param "PROJECT_DIR"))
        (require-not
            (require-any
                (regex #"/\\.git/")        ; .gitディレクトリは除外
                (regex #"\\.lock$")        ; lockファイルは除外
            )
        )
    )
)
```

### ネットワークアクセスの制限

```scheme
;; 外部への通信を拒否
(deny network-outbound)

;; 特定のサービスのみ許可
(allow network-outbound
    (require-any
        (remote tcp "api.anthropic.com:443")
        (remote tcp "github.com:443")
        (remote tcp "registry.npmjs.org:443")
    )
)

;; ローカルサーバーの起動を許可
(allow network-inbound
    (local tcp "*:3000-9999")  ; 開発用ポート範囲
)
```

### プロセス実行の制限

```scheme
;; すべてのプロセス実行を拒否
(deny process-exec)

;; 必要なコマンドのみ許可
(allow process-exec
    (require-any
        (literal "/usr/bin/node")
        (literal "/usr/bin/npm")
        (literal "/usr/bin/git")
        (subpath "/opt/homebrew/bin/")
    )
)
```

## デバッグのためのTips

以下のコマンドを実行すると、Sandboxによって拒否された操作をリアルタイムで確認できます。

```bash
sudo log stream --predicate 'sender == "Sandbox"' | grep deny
```

**出力例**
```
Sandbox: claude(12345) deny(1) file-write-create /Users/username/.env
Sandbox: claude(12345) deny(1) file-write-data /etc/hosts
```

### with-no-log: ログ出力の抑制

一部の操作は頻繁に拒否されるため、ログが大量に出力されることがあります。`with-no-log`を使用することで、特定のルールのログ出力を抑制できます。

```scheme
;; ログを出力せずに拒否
(deny file-read* (with-no-log)
    (subpath "/System/Library/")
)
```

### debug: デバッグ用のメッセージ出力

開発時に、どのルールが適用されているかを確認するためのメッセージを出力できます。

```scheme
;; デバッグメッセージ付きで許可
(allow file-write* (with-report)
    (subpath (param "TARGET_DIR"))
)
```

:::message
`with-report`は一部のmacOSバージョンでのみ利用可能です。
:::

# Claude Code向けSandbox設定の実装

ここでは、Claude Codeを安全に実行するための実践的なSandbox設定を紹介します。

## Sandbox Profileファイルの作成

:::message
前述したログ出力を用いつつ、各々の環境に合わせてファイルの内容を微調整することをおすすめします。
:::

以下の内容で`profile.sb`ファイルを作成します。

```scheme:profile.sb
(version 1)

;; デフォルトで全て拒否（ホワイトリスト方式）
(deny default)

;; =====================================
;; ネットワーク制御
;; =====================================
(allow network-outbound)
(allow network-inbound)

;; =====================================
;; Keychain アクセス（認証情報保存のため必要）
;; =====================================
(allow file-read*
    (subpath (string-append (param "HOME_DIR") "/Library/Keychains"))
    (literal "/Library/Keychains/System.keychain")
)
(allow file-write*
    (subpath (string-append (param "HOME_DIR") "/Library/Keychains"))
)

;; =====================================
;; ファイル読み込み制限
;; =====================================
;; .envファイルの読み込みを明示的に拒否（シークレット保護）
(deny file-read*
    (regex #"\.env.*$")
    (regex #".*\.env$")
)
;; その他は全て読み込み許可
(allow file-read*)

;; =====================================
;; ファイル書き込み制限
;; =====================================
;; デフォルトで書き込みを拒否
(deny file-write*)

;; プロジェクトディレクトリへの書き込みのみ許可
(allow file-write*
    (subpath (param "TARGET_DIR"))
)

;; Claude設定ファイルへの書き込みを許可
(allow file-write*
    (regex (string-append "^" (param "HOME_DIR") "/.claude.*"))
)

;; npmパッケージのインストールを許可
(allow file-write*
    (subpath (string-append (param "HOME_DIR") "/.npm"))
)

;; 一時ファイル関連ディレクトリへの書き込みを許可
(allow file-write*
    (subpath "/tmp")
    (subpath "/private/tmp")
    (subpath "/var/folders")
    (subpath "/private/var/folders")
    (subpath (string-append (param "HOME_DIR") "/.cache"))
    (subpath (string-append (param "HOME_DIR") "/Library/Caches"))
)
```

## 実行方法

```bash
# Sandbox内でClaude Codeを起動
sandbox-exec \
  -f profile.sb \
  -D TARGET_DIR="$(pwd)" \
  -D HOME_DIR="$HOME" \
  claude
```

**パラメータ解説**
- `-f`: Sandbox Profileファイルのパス
- `-D`: プロファイル内で使用する変数を定義（`param`で参照）
- `TARGET_DIR`: プロジェクトディレクトリ（書き込み許可）
- `HOME_DIR`: ホームディレクトリ（設定ファイル等で使用）

## エイリアス登録

毎回長いコマンドを入力するのは手間がかかります。`.zshrc`や`.bashrc`にエイリアスを登録しておくと便利です。

```bash
# ~/.zshrc に追加
alias claude-sandbox='sandbox-exec -f ~/profile.sb -D TARGET_DIR="$(pwd)" -D HOME_DIR="$HOME" claude'
```

以降は`claude-sandbox`コマンドで起動できます。

# Claude Codeのそのほかのセキュリティアプローチとの比較

Claude Code公式では、セキュリティを強化する方法として主に3つの手法が紹介されています（2025年11月現在）。ここでは、それぞれの特徴と使い分けを詳しく解説し、本記事で紹介する手法を含めた4つのアプローチを比較します。

## 1. Claude Code Sandbox（公式サンドボックス機能）

Claude Code公式が提供するサンドボックス機能です。macOSでは内部的にApple Seatbeltを使用し、Bashコマンドをファイルシステムとネットワークから隔離します。

参考: [公式ドキュメント - Sandboxing](https://docs.claude.com/en/docs/claude-code/sandboxing)

**主な特徴**

- Apple Seatbeltによるカーネルレベルの隔離（[オープンソース実装](https://github.com/anthropic-experimental/sandbox-runtime)）
- 禁止操作は即座に失敗し、エラーメッセージが表示されます

:::message
筆者の環境では、sandboxを解除し実行してしまう事案が発生してしまいました...
![Claude Codeの実行メッセージ](https://storage.googleapis.com/zenn-user-upload/435a6d98318e-20251103.png)
:::

**設定方法**

```json:.claude/settings.json
{
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "excludedCommands": ["docker"],
    "network": {
      "allowUnixSockets": [
        "/var/run/docker.sock"
      ],
      "allowLocalBinding": true
    }
  },
  "permissions": {
    "deny": [
      "Read(.envrc)",
      "Read(~/.aws/**)"
    ]
  }
}
```

詳細設定については [公式ドキュメント - Sandbox Settings](https://docs.claude.com/en/docs/claude-code/settings#sandbox-settings) を参照してください。

## 2. Claude Code Permission Settings（パーミッション設定）

ツール実行前に許可・拒否・確認を求める、アプリケーションレベルの権限管理機能です。

参考: [公式ドキュメント - Permission Settings](https://docs.claude.com/en/docs/claude-code/settings#permission-settings)

**主な特徴**

- **3種類のルール**: `allow`（許可）、`ask`（確認）、`deny`（拒否）でツール実行を制御
- **ツール単位の権限管理**: `Bash(...)`, `Read(...)`, `Edit(...)`, `WebFetch`など、ツールごとに権限設定
- **機密情報の保護**: `deny`で`.env`ファイルやsecretsディレクトリへのアクセスを遮断可能
- **Bashルールは接頭辞マッチ**: `Bash(curl:*)`は正規表現でなく前方一致（回避可能性に留意）

**設定方法**

```json:.claude/settings.json
{
  "permissions": {
    "allow": [
      "Bash(npm run lint)",
      "Bash(npm run test:*)",
      "Read(~/.zshrc)"
    ],
    "ask": [
      "Bash(git push:*)",
      "Write(*.env)"
    ],
    "deny": [
      "Bash(curl:*)",
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)",
      "WebFetch"
    ],
    "additionalDirectories": [
      "../docs/"
    ],
    "defaultMode": "acceptEdits"
  }
}
```

## 3. DevContainer（開発コンテナ）

VS CodeのDev Containers拡張機能と連携し、コンテナ化された開発環境でClaude Codeを実行する方法です。

参考: [公式ドキュメント - Development containers](https://docs.claude.com/en/docs/claude-code/devcontainer)

**主な特徴**

- **環境隔離**: ホストシステムから完全に分離された環境を提供
- **再現性**: チーム全体で同一の開発環境を共有
- **セキュリティ**: デフォルト拒否のファイアウォールルール（npm registry、GitHub、Claude APIなどのみ許可）
- **永続化**: コマンド履歴や設定を再起動後も保持
- **クロスプラットフォーム**: macOS、Windows、Linuxすべてで動作

**設定方法**

1. [公式リポジトリ](https://github.com/anthropics/claude-code/tree/b42fd9928c8f80ead5ca43e4e0673da22faca6bd/.devcontainer)から`.devcontainer`ディレクトリをプロジェクトルートに配置
2. VS CodeでDev Containers拡張機能をインストール
3. コマンドパレットから「Dev Containers: Reopen in Container」を実行

## それぞれのアプローチの比較

| 項目 | Claude Code Sandbox | Claude Code Permission Settings | DevContainer | SBPL自前用意（この記事で紹介する手法） |
|------|---------------------|----------------------------------|---------------------|--------------|
| **設定の簡単さ** | ◎ JSONで設定 | ◎ JSONで設定 | △ devcontainer設定が必要、初回起動は時間がかかる。多くの場合、プロジェクトごとの設定ファイルが必要 | ○ SBPLの記述が必要。複数プロジェクトで使いまわしやすい |
| **制御レベル** | ◎ カーネルレベル | △ アプリケーションレベル | ◎ コンテナレベル（名前空間隔離） | ◎ カーネルレベル |
| **制御範囲** | △ Claude Code実行中のBashコマンド | △ Claude Codeのツール実行 | ◎ コンテナ内の全プロセス | ◎ sandbox-execで起動したプロセス全体 |
| **オーバーヘッド** | ◎ ほぼなし | ◎ ほぼなし | △ コンテナ起動・リソース消費あり | ◎ ほぼなし |
| **他ツールへの適用** | × Claude Code専用 | × Claude Code専用 | ◎ 任意の開発環境に適用可能 | ◎ 任意のコマンドに適用可能 |
| **対応OS** | ○ macOS、Linux | ◎ 全OS | ◎ 全OS（Docker対応環境） | △ macOSのみ |

それぞれの手法には明確な適用シーンがあります。

**Claude Code Sandbox / Permission Settings**

Claude Code利用者にとって最も手軽な選択肢です。JSONファイルの設定だけで即座に使い始められるため、まず最初に導入すべき基本的なセキュリティ対策といえます。

**DevContainer**

コンテナによる完全な環境隔離が可能で、チーム開発での再現性に優れています。特にクロスプラットフォームで統一環境が求められるプロジェクトに最適です。

ただし、コンテナ起動には数秒〜数十秒のオーバーヘッドがあります。メモリやディスク容量も追加で消費するため、日常的な開発作業では待ち時間が気になる場面もあります。

**SBPL自前用意（本記事の手法）**

macOS環境において最も柔軟かつ高性能な選択肢です。カーネルレベルでの細かい制御が可能でありながら、**ほぼオーバーヘッドなし**で動作します。

コンテナのような起動待ち時間はありません。ネイティブなプロセス実行速度を維持しつつ、以下のような細かい制御が可能です：

- 正規表現による詳細なパス制御
- 送受信を別々に管理できるネットワーク制御
- システムコールレベルでの権限管理

Claude Code以外の任意のコマンドやツールにも適用できるため、汎用性の高いセキュリティ基盤として機能します。

DevContainerは「完全な隔離環境」という点で優れています。しかし、日常的な開発フローでは、起動コストやリソース消費が開発体験を損なう可能性があります。SBPL自前用意は、カーネルレベルの保護を維持しながら**プロセス起動時のオーバーヘッドをほぼゼロ**に抑えられます。パフォーマンスとセキュリティの両立が求められるmacOS開発者にとって理想的な選択肢です。

# まとめ

AI Agentツールは、開発者の生産性を劇的に向上させる強力な存在です。しかし、[大いなる力には、大いなる責任が伴う](https://ja.wikipedia.org/wiki/%E5%A4%A7%E3%81%84%E3%81%AA%E3%82%8B%E5%8A%9B%E3%81%AB%E3%81%AF%E3%80%81%E5%A4%A7%E3%81%84%E3%81%AA%E3%82%8B%E8%B2%AC%E4%BB%BB%E3%81%8C%E4%BC%B4%E3%81%86) という言葉が示すとおり、その強力さゆえに適切な制御と防御が不可欠です。本記事で紹介したApple Seatbeltによるサンドボックス化は、ほぼオーバーヘッドなしでカーネルレベルの保護を実現できるmacOS開発者にとって理想的な手法です。機密情報の漏洩を防ぎ、意図しないファイル操作を抑止し、ネットワーク通信を適切に制御することで、AI Agentの力を最大限に活かしつつリスクを最小化できます。セキュリティは一度設定して終わりではなく、継続的な見直しと改善が必要です。本記事の内容を参考に、皆さんの環境に合わせた適切な防御策を講じ、安心安全なAI Agent活用を目指しましょう！

# 参考文献

- [Sandbox operations - Apple Developer (非公式逆引き)](https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf)
- [Apple Developer: App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [macOS Security and Privacy Guide](https://github.com/drduh/macOS-Security-and-Privacy-Guide)
- [The principle of Defense-in-Depth](https://cheatsheetseries.owasp.org/cheatsheets/Secure_Product_Design_Cheat_Sheet.html#2-the-principle-of-defense-in-depth)
