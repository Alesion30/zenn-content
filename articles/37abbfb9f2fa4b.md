---
title: "macOSで手軽にSandbox環境を構築できるApple Seatbeltの実践ガイド"
emoji: "🔒"
type: "tech"
topics: ["mac", "security", "ai", "claudeCode", "appleSeatbelt"]
published: false
---

# TL;DR

- Apple Seatbeltは、macOSに組み込まれたサンドボックス機構です。ファイルアクセスやネットワーク通信を細かく制限できます
- LLMベースのAI Agentツールは広範囲にファイルシステムへアクセスできるため、セキュリティ上の懸念があります。Apple Seatbeltはその有効な対策となります
- DevContainerは完全な隔離環境を提供しますが、起動に数秒〜数十秒かかります。Apple Seatbeltは起動オーバーヘッドがほぼゼロで、カーネルレベルの保護を実現します
- 本記事では、Claude Codeを例にApple Seatbeltの実践的な使い方を紹介します

# 想定読者と前提知識

**想定読者**
- macOSでClaude CodeやCursor等のAI Agentツールを使用している開発者
- AI Agentの実行権限を制限し、セキュリティを強化したい方
- macOSのサンドボックス機構に興味がある方

**前提知識**
- macOSの基本的なターミナル操作

**本記事で扱わないこと**
- macOS以外でのサンドボックス機構
- Dockerを使用した仮想化による隔離

# Apple Seatbeltとは

Apple Seatbeltは、macOSに標準搭載されているサンドボックス機構です。アプリケーションやプロセスに対して、ファイルシステム、ネットワーク、プロセス間通信などのリソースアクセスを細かく制限できます。

参考: [Sandbox operations - Apple Developer (非公式逆引き)](https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf)

## 動作の仕組み

Apple Seatbeltは、macOSのカーネルレベルで動作する強制アクセス制御（MAC: Mandatory Access Control）機構です。プロセスに対して以下の流れでアクセス制御を行います：

1. **プロファイルの読み込み**: `sandbox-exec`コマンドで、プロセス起動時にセキュリティプロファイルを適用します
2. **カーネルによる監視**: プロセスがシステムコールを実行するたびに、カーネルがプロファイルと照合します
3. **許可/拒否の判定**: プロファイルのルールに基づいて、操作を許可または拒否します

プロファイルは **SBPL（Sandbox Profile Language）** という専用言語で記述します。SBPLはSchemeライクな[S式](https://ja.wikipedia.org/wiki/S%E5%BC%8F)による宣言的な設定形式です。「このディレクトリ以下への書き込みは許可するが、.envファイルの読み込みは拒否する」といった細かいルールを柔軟に定義できます。

## 使用方法の概要

ターミナルから以下のように使用します：

```bash
# sandbox-execコマンドでプロファイルを適用してプログラムを実行
sandbox-exec -f profile.sb プログラム名
```

`profile.sb`はSBPLで記述されたプロファイルファイルです。この仕組みにより、既存のアプリケーションを変更することなく、実行時にサンドボックス環境を構築できます。

## 主な特徴

- **軽量**: コンテナやVMと異なり、ほぼオーバーヘッドなしで動作します
- **柔軟な制御**: SBPLによる細かい権限設定が可能です（詳細は後述）
- **システム統合**: macOSに標準搭載されており、`sandbox-exec`コマンドで即座に利用できます
- **既存プログラムへの適用**: プログラム自体を変更せず、実行時にサンドボックス化できます

## Appleは非推奨としているが、広く使われている技術

Appleは公式にApple Seatbeltのドキュメントを公開していません。しかし、実際には多くのアプリケーションやツールで使用されています。

**採用事例**
- **iOS/macOSアプリ**: すべてのiOSアプリはサンドボックス内で実行される（ただし、現在は[App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)が推奨される）
- **Chromium**: macOS版ChromiumでApple Seatbeltを適用（[sandbox/mac ディレクトリ](https://github.com/chromium/chromium/tree/main/sandbox/mac)、Sandbox Profile: [`renderer.sb`](https://chromium.googlesource.com/chromium/src/+/770eff8/sandbox/policy/mac/renderer.sb)、[`gpu.sb`](https://chromium.googlesource.com/chromium/src/+/770eff8/sandbox/policy/mac/gpu.sb)）
- **AI Agentツール**:
  - **Claude Code**: macOSでApple Seatbeltを使用してファイルシステムとネットワークを隔離（[公式ドキュメント](https://docs.claude.com/en/docs/claude-code/sandboxing)、[オープンソース実装](https://github.com/anthropic-experimental/sandbox-runtime)）
  - **Gemini CLI**: macOS向けSBPLファイルを公開（[`sandbox-macos-permissive-open.sb`](https://github.com/google-gemini/gemini-cli/blob/main/packages/cli/src/utils/sandbox-macos-permissive-open.sb)）

補足: Appleはアプリ配布や製品用途ではエンタイトルメントベースのApp Sandboxを推奨しています（[Apple Developer: App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)）。一方、`sandbox-exec`による動的プロファイルはドキュメントが限られており、主に開発・検証やプロセス単位の一時的な制限に適した手法です。

# SBPL（Sandbox Profile Language）の基本

SBPLはSchemeライクな[S式](https://ja.wikipedia.org/wiki/S%E5%BC%8F)で許可・拒否ルールを定義する言語です。

## 基本構文

```scheme
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

## 主要な操作タイプ

| 操作 | 説明 |
|------|------|
| `file-read*` | ファイル読み込み |
| `file-write*` | ファイル書き込み |
| `network-outbound` | 外部への通信 |
| `network-inbound` | 外部からの通信受信 |
| `process-exec` | プロセス実行 |
| `ipc-posix-shm` | 共有メモリ |

## 条件指定の方法

```scheme
;; パス指定
(literal "/exact/path")           ; 完全一致
(subpath "/directory/")           ; サブディレクトリ含む
(regex #"\.env$")                 ; 正規表現

;; パラメータ使用
(subpath (param "TARGET_DIR"))    ; 実行時に渡されるパラメータ
(string-append (param "HOME") "/Documents")  ; 文字列結合
```

# Claude Code向けSandbox設定の実装

ここでは、Claude Codeを安全に実行するための実践的なSandbox設定を紹介します。

## Sandbox Profileファイルの作成

以下の内容で`sandbox-macos-permissive-open.sb`ファイルを作成します。

```scheme
(version 1)

;; デフォルトで全て拒否（ホワイトリスト方式）
(deny default)

;; =====================================
;; ネットワーク制御
;; =====================================
;; AI AgentはAPI通信が必要なため、外部通信は許可
(allow network-outbound)
;; サーバーとして動作させないため、受信は拒否
(deny network-inbound)

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
;; ファイル書き込み制限（最も重要）
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

;; シェル環境への書き込みを許可
(allow file-write*
    (subpath (string-append (param "HOME_DIR") "/.local"))
    (subpath (string-append (param "HOME_DIR") "/.zplug"))
)

;; 標準入出力デバイス
(allow file-write*
    (literal "/dev/stdout")
    (literal "/dev/stderr")
    (literal "/dev/null")
    (literal "/dev/dtracehelper")
    (regex #"^/dev/tty.*")
)
```

## 実行方法

```bash
# Sandbox内でClaude Codeを起動
sandbox-exec \
  -f sandbox-macos-permissive-open.sb \
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
alias claude-sandbox='sandbox-exec -f ~/sandbox-macos-permissive-open.sb -D TARGET_DIR="$(pwd)" -D HOME_DIR="$HOME" claude'
```

以降は`claude-sandbox`コマンドで起動できます。

## ログ出力の監視によるデバッグ方法

別のターミナルで以下のコマンドを実行すると、Sandboxによって拒否された操作をリアルタイムで確認できます。

```bash
sudo log stream --predicate 'sender == "Sandbox"' | grep deny
```

**出力例**
```
Sandbox: claude(12345) deny(1) file-write-create /Users/username/.env
Sandbox: claude(12345) deny(1) file-write-data /etc/hosts
```

## 段階的なプロファイル調整

初めてSandboxを構築する際は、以下の手順で段階的に調整していきます。

1. **すべて拒否から開始**: `(deny default)`で始めます
2. **ログ監視**: アプリケーションを使いながら、どのような操作が行われているか確認します
3. **段階的に制限**: 不要な操作を特定して`deny`ルールを追加します
4. **必要な操作を許可**: `deny`により動作しなくなった部分を、条件付き`allow`で許可します

## テスト用コマンド

Sandboxが正しく機能しているか確認するためのテストコマンドです。

```bash
# 現在のディレクトリへの書き込み（許可されるべき）
echo "test" > test.txt

# .envファイルの読み込み（拒否されるべき）
cat ~/.env

# ホームディレクトリへの書き込み（拒否されるべき）
echo "test" > ~/test.txt

# /tmpへの書き込み（許可されるべき）
echo "test" > /tmp/test.txt
```

# 他のSandbox技術との比較

## macOS以外のOS

| 技術 | OS | 特徴 |
|------|-----|------|
| **SELinux** | Linux | ラベルベースのMAC、高度だが複雑 |
| **AppArmor** | Linux | パスベース、SELinuxより簡単 |
| **seccomp** | Linux | システムコールレベルで制限、軽量 |
| **seccomp-bpf** | Linux | BPFによる柔軟なフィルタリング |

## 仮想化/コンテナ技術

| 技術 | 特徴 | ユースケース |
|------|------|--------------|
| **Docker** | コンテナ仮想化、環境隔離 | 本番環境、CI/CD |
| **Windows Sandbox** | 軽量VM、使い捨て環境 | マルウェア解析 |
| **DevContainer** | VS Code統合、再現性 | 開発環境統一 |

## Apple Seatbeltのメリット・デメリット

### メリット

- **軽量**: ほぼオーバーヘッドなし
- **即座に利用可能**: macOSへ標準搭載
- **プロセス単位で制御**: 既存の環境を変更せず、特定のプロセスのみ制限
- **細かい制御**: ファイルパス、ネットワーク、IPCなど詳細な設定が可能

### デメリット

- **非公式**: 仕様変更のリスク
- **ドキュメント不足**: 試行錯誤が必要
- **macOS専用**: 他OSでは使用不可
- **完全な隔離ではない**: カーネルレベルの脆弱性には対応できない

# Claude Codeのセキュリティ設定：4つのアプローチ比較

Claude Code公式では、セキュリティを強化する方法として主に3つの手法が紹介されています（2025年11月現在）。ここでは、それぞれの特徴と使い分けを詳しく解説し、本記事で紹介する手法を含めた4つのアプローチを比較します。

## 1. Claude Code Sandbox（公式サンドボックス機能）

Claude Code公式が提供するサンドボックス機能です。macOSでは内部的にApple Seatbeltを使用し、Bashコマンドをファイルシステムとネットワークから隔離します。

参考: [公式ドキュメント - Sandboxing](https://docs.claude.com/en/docs/claude-code/sandboxing)

**設定方法**

```json
// .claude/settings.json
{
  "sandbox": {
    "enabled": true,
  }
}
```

詳細設定については [公式ドキュメント - Sandbox Settings](https://docs.claude.com/en/docs/claude-code/settings#sandbox-settings) を参照してください。

**公式実装の特徴**

- Apple Seatbeltによるカーネルレベルの隔離（[オープンソース実装](https://github.com/anthropic-experimental/sandbox-runtime)）
- 禁止操作は即座に失敗し、エラーメッセージが表示されます

:::message
筆者の環境では、sandboxを解除し実行してしまう事象が発生してしまいました...
![Claude Codeの実行メッセージ](https://storage.googleapis.com/zenn-user-upload/435a6d98318e-20251103.png)
:::

## 2. Claude Code Permission Settings（パーミッション設定）

ツール実行前に許可・拒否・確認を求める、アプリケーションレベルの権限管理機能です。

参考: [公式ドキュメント - Permission Settings](https://docs.claude.com/en/docs/claude-code/settings#permission-settings)

**設定方法**

```json
// .claude/settings.json
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

**主な設定項目**

- `allow`: 自動的に許可するツール/パターン
- `ask`: 実行前に確認を求める
- `deny`: 完全に拒否する
- `additionalDirectories`: アクセス可能な追加ディレクトリ
- `defaultMode`: デフォルトの権限モード（`acceptEdits`、`standard`、`bypassPermissions`）

**パターン例**

- `Bash(git diff:*)`: `git diff`で始まるコマンドを許可
- `Read(./secrets/**)`: `secrets/`以下のすべてのファイル読み込みを拒否
- `Write(*.env)`: `.env`ファイルへの書き込みを制限

## 3. DevContainer（開発コンテナ）

VS CodeのDev Containers拡張機能と連携し、コンテナ化された開発環境でClaude Codeを実行する方法です。

参考: [公式ドキュメント - Development containers](https://docs.claude.com/en/docs/claude-code/devcontainer)

**概要**

- Node.js 20ベースの事前設定済みコンテナ
- カスタムファイアウォール（`init-firewall.sh`）によるネットワーク制限
- devcontainer.json、Dockerfile、init-firewall.shの3つのファイルで構成されます
- `--dangerously-skip-permissions`フラグで、パーミッションプロンプトをバイパス可能（無人実行用）

**主な特徴**

- **環境隔離**: ホストシステムから完全に分離された環境を提供します
- **再現性**: チーム全体で同一の開発環境を共有できます
- **セキュリティ**: デフォルト拒否のファイアウォールルール（npm registry、GitHub、Claude APIなどのみ許可）
- **永続化**: コマンド履歴や設定を再起動後も保持します
- **クロスプラットフォーム**: macOS、Windows、Linuxすべてで動作します

## 4つのアプローチの比較表

| 項目 | Claude Code Sandbox | Claude Code Permission Settings | DevContainer | SBPL自前用意（この記事で紹介する手法） |
|------|---------------------|----------------------------------|---------------------|--------------|
| **設定の簡単さ** | ◎ JSONで設定、IDE統合 | ◎ JSONで設定、パターンマッチング | ○ devcontainer設定が必要、初回起動は時間がかかる | △ SBPL記述が必要 |
| **制御レベル** | カーネルレベル | アプリケーションレベル | コンテナレベル（名前空間隔離） | カーネルレベル |
| **制御の細かさ** | ○ 主要なパスとネットワークを制御 | ◎ ツール単位、パターンマッチング | ○ ファイアウォールルール、ボリュームマウント | ◎ 最も詳細（正規表現、システムコール等） |
| **保守性** | ◎ 公式サポート | ◎ 公式サポート | ◎ 公式サポート、Docker/VS Code標準技術 | △ 仕様変更リスクあり |
| **ネットワーク制御** | ◎ 送受信を別々に制御 | ○ WebFetchの許可/拒否 | ◎ ファイアウォールで詳細に制御（ホワイトリスト方式） | ◎ 送受信を別々に制御、ポート指定も可能 |
| **環境変数保護** | ◎ denyFSReadsで指定 | ◎ Read(パス)で拒否 | ◎ ボリュームマウント設定で制御 | ◎ 正規表現で詳細に指定 |
| **ユーザー確認** | なし（即座に拒否） | あり（askルール） | なし（--dangerously-skip-permissions時） | なし（即座に拒否） |
| **対象範囲** | Claude Code実行中のBashコマンド | Claude Codeのツール実行 | コンテナ内の全プロセス | sandbox-execで起動したプロセス全体 |
| **デバッグ容易性** | ○ Claude Code内でエラー表示 | ◎ 実行前確認、ログ表示 | △ コンテナログ確認が必要 | △ `log stream`で監視が必要 |
| **環境隔離の強度** | △ プロセス単位 | △ アプリケーション制御のみ | ◎ 完全な環境分離 | △ プロセス単位 |
| **オーバーヘッド** | ほぼなし | ほぼなし | ○ コンテナ起動・リソース消費あり | ほぼなし |
| **他ツールへの適用** | × Claude Code専用 | × Claude Code専用 | ◎ 任意の開発環境に適用可能 | ◎ 任意のコマンドに適用可能 |
| **対応OS** | macOS、Linux | 全OS | 全OS（Docker対応環境） | macOSのみ |
| **チーム開発** | △ 設定ファイル共有のみ | △ 設定ファイル共有のみ | ◎ 環境全体を共有、再現性が高い | △ macOSユーザーのみ |

## 各アプローチの使い分け

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

Apple Seatbeltは、macOSで手軽にサンドボックス環境を構築できる強力な技術です。仕様は非公開で非推奨とされていますが、ChromiumやElectronベースの多くのアプリケーションで実績があります。

AI Agentツールは強力な自動化能力を持つ一方で、誤操作やプロンプトインジェクションによるリスクがあります：

- 機密情報の読み取り
- 不要なファイルの書き込み
- 過剰な外部通信

Apple Seatbeltは、これらのリスクに対して特に有効です。機密ファイルの保護、不要な書き込みの抑止、ネットワーク制御など、細かいセキュリティ設定が可能です。

OSネイティブのサンドボックスは、多層防御（Defense in Depth）の重要な一部です。IDEやツール側のpermissions、ファイル権限、ネットワーク制御などと組み合わせることで、より安全な開発環境を構築できます。最小権限の原則と段階的な許可を徹底することで、AI時代の開発体験を安全に保つことができるでしょう。

# 参考文献

- [Sandbox operations - Apple Developer (非公式逆引き)](https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf)
- [Apple Developer: App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [macOS Security and Privacy Guide](https://github.com/drduh/macOS-Security-and-Privacy-Guide)
- [The principle of Defense-in-Depth](https://cheatsheetseries.owasp.org/cheatsheets/Secure_Product_Design_Cheat_Sheet.html#2-the-principle-of-defense-in-depth)
