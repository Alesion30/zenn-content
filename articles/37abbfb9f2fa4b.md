---
title: "macOSで手軽にSandbox環境を構築できるApple Seatbeltの実践ガイド"
emoji: "🔒"
type: "tech"
topics: ["macos", "security", "sandbox", "ai", "claude"]
published: false
---

# TL;DR

Apple Seatbeltは、macOSに組み込まれたサンドボックス機構で、ファイルアクセスやネットワーク通信を制限できます。`sandbox-exec`コマンドとSBPL（Sandbox Profile Language）ファイルを使って、AI AgentツールやCLIアプリケーションの実行環境を簡単に制限可能です。本記事では、Claude CodeやCursor等のAI Agentツールを安全に使用するための具体的な実装方法を解説します。

# 想定読者と前提知識

**想定読者**
- macOSでClaude CodeやCursor等のAI Agentツールを使用している開発者
- AI Agentの実行権限を制限し、セキュリティを強化したい方
- macOSのサンドボックス機構に興味がある方

**前提知識**
- macOSの基本的なターミナル操作
- 環境変数やファイルパーミッションの基礎知識

**実行環境**
- macOS 10.5以降（本記事ではmacOS 14 Sonoma以降を推奨）
- zshまたはbash

**本記事で扱わないこと**
- iOS/iPadOSのサンドボックス機構
- Windowsでのサンドボックス実装
- Dockerを使用した仮想化による隔離

# Apple Seatbeltとは

Apple Seatbeltは、macOSに組み込まれているサンドボックス機構です。アプリケーションやプロセスに対してファイルシステム、ネットワーク、プロセス間通信等のリソースアクセスを細かく制限できます。

## 主な特徴

- **軽量**: コンテナやVMと異なり、ほぼオーバーヘッドなしで動作
- **柔軟な制御**: SBPL（Sandbox Profile Language）による細かい権限設定が可能
- **システム統合**: macOSのセキュリティ機構と統合されており、`sandbox-exec`コマンドで即座に利用可能
- **実績**: iOSアプリ、Chromium、VS Code等で実際に使用されている

## 非公式だが広く使われている技術

Appleは公式にSeatbeltのドキュメントを公開していませんが、実際には多くのアプリケーションで使用されています。

**採用事例**
- **iOS/macOSアプリ**: すべてのiOSアプリはサンドボックス内で実行される
- **Chromium**: macOS版Chromiumのレンダラープロセスで使用（[GitHubリポジトリ](https://github.com/chromium/chromium/tree/main/sandbox/mac)）
- **AI Agentツール**: Claude Code、Cursor等で実行環境の制限に使用

最近では、LLMベースのAI Agentツールがファイルシステムへ広範囲にアクセスできることからセキュリティ上の懸念が高まっており、これらのツールでもSeatbeltが注目されています。

# SBPL（Sandbox Profile Language）の基本

SBPLはSchemeライクなS式を使用して、許可・拒否ルールを定義します。

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
;; sandbox-exec -f sandbox-macos-permissive-open.sb -D TARGET_DIR="$(pwd)" -D HOME_DIR="$HOME" claude
;; NOTE(log確認方法): sudo log stream --predicate 'sender == "Sandbox"' | grep deny

(version 1)

;; デフォルトで全て許可（ホワイトリスト方式ではなく、ブラックリスト方式）
(allow default)

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

毎回長いコマンドを打つのは面倒なため、`.zshrc`や`.bashrc`へエイリアスを登録します。

```bash
# ~/.zshrc に追加
alias claude-sandbox='sandbox-exec -f ~/sandbox-macos-permissive-open.sb -D TARGET_DIR="$(pwd)" -D HOME_DIR="$HOME" claude'
```

以降は`claude-sandbox`コマンドで起動できます。

# Sandbox動作の検証とデバッグ

Sandboxが意図通りに動作しているかを確認する方法を紹介します。

## ログ出力の監視

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

初めてSandboxを構築する際は、以下の手順で段階的に調整すると良いでしょう。

1. **すべて許可から開始**: `(allow default)`で始める
2. **ログ監視**: アプリケーションを使いながら、どのような操作が行われているか確認
3. **段階的に制限**: 不要な操作を特定して`deny`ルールを追加
4. **必要な操作を許可**: `deny`により動作しなくなった部分を条件付き`allow`で許可

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
| **Devcontainer** | VS Code統合、再現性 | 開発環境統一 |

## Apple Seatbeltのメリット

- **軽量**: ほぼオーバーヘッドなし
- **即座に利用可能**: macOSへ標準搭載
- **プロセス単位で制御**: 既存の環境を変更せず、特定のプロセスのみ制限
- **細かい制御**: ファイルパス、ネットワーク、IPCなど詳細な設定が可能

## デメリット

- **非公式**: 仕様変更のリスク
- **ドキュメント不足**: 試行錯誤が必要
- **macOS専用**: 他OSでは使用不可
- **完全な隔離ではない**: カーネルレベルの脆弱性には対応できない

# Claude Code公式のSandbox機能との比較

Claude Codeには、バージョン0.8.0から公式のSandbox機能が実装されています。公式実装と自前のSeatbelt実装を比較します。

## 公式Sandbox機能（settings.json）

```json
{
  "claude.sandboxing.mode": "restricted",
  "claude.sandboxing.allowedDirectories": [
    "${workspaceFolder}"
  ]
}
```

## 比較

| 項目 | 公式Sandbox | Seatbelt自前実装 |
|------|-------------|------------------|
| **設定の簡単さ** | ◎ GUIで設定可能 | △ SBPLファイル作成が必要 |
| **制御の細かさ** | △ 設定項目が限定的 | ◎ 詳細に制御可能 |
| **保守性** | ◎ 公式サポート | △ 仕様変更リスク |
| **ネットワーク制御** | △ 制限項目が少ない | ◎ 送受信を別々に制御 |
| **環境変数保護** | △ 設定なし | ◎ .envファイルを明示的に拒否 |

## 推奨される使い分け

- **公式Sandboxで十分なケース**: 一般的な開発プロジェクト、設定を簡単にしたい場合
- **Seatbelt自前実装が適しているケース**:
  - 機密情報を扱うプロジェクト
  - 細かいアクセス制御が必要な場合
  - 複数のAI Agentツールを統一的に制限したい場合

# AI Agentのセキュリティにおける多層防御

AI Agentを安全に使用するには、単一の防御策に頼らず、複数の層で防御する「Defense in Depth（多層防御）」が重要とされています。

## 推奨される防御層

```
┌─────────────────────────────────────┐
│ 1. コード監視・承認（人間の確認） │  ← 最終防衛線
├─────────────────────────────────────┤
│ 2. Sandbox（Seatbelt等）           │  ← 本記事の内容
├─────────────────────────────────────┤
│ 3. ファイルシステム権限             │  ← chmod, chown等
├─────────────────────────────────────┤
│ 4. ネットワーク分離                 │  ← ファイアウォール
├─────────────────────────────────────┤
│ 5. 環境変数・シークレット管理       │  ← Vault等
├─────────────────────────────────────┤
│ 6. 読み取り専用マウント             │  ← Docker volume等
└─────────────────────────────────────┘
```

## 実践的な組み合わせ例

```bash
# 1. プロジェクトディレクトリを制限
cd ~/projects/safe-project

# 2. 機密ディレクトリを読み取り専用に
chmod -R 444 ~/projects/safe-project/.secrets

# 3. Seatbelt Sandboxで起動
sandbox-exec -f ~/sandbox-macos-permissive-open.sb \
  -D TARGET_DIR="$(pwd)" \
  -D HOME_DIR="$HOME" \
  claude

# 4. ネットワークをVPN経由に制限（別途設定）
```

## 完全な安全はないことを理解する

どれほど防御しても、以下のリスクは残ることを認識しておきましょう。

- **LLMの出力品質**: 意図しないコードを生成する可能性
- **プロンプトインジェクション**: 悪意のある指示を埋め込まれるリスク
- **ゼロデイ脆弱性**: Sandbox自体の脆弱性
- **人的ミス**: 設定ミス、不注意な承認

そのため、最終的には**人間による確認と判断**が不可欠です。

# まとめ

Apple Seatbeltは、macOSで手軽にサンドボックス環境を構築できる強力な技術です。非公式ではあるものの、Chromiumや多くのアプリケーションで実績があり、AI Agentツールのセキュリティ強化に有効です。

**本記事のポイント**
- `sandbox-exec`とSBPLファイルで即座にSandbox環境を構築可能
- ファイル読み書き、ネットワーク通信等を細かく制御できる
- Claude Code等のAI Agentツールの実行権限を制限し、安全性を向上
- 公式Sandbox機能と併用することで、より強固な防御が可能
- 多層防御の一環として活用し、最終的には人間の確認が重要

**次のステップ**
- 本記事のSBPLファイルをカスタマイズして、自分のプロジェクトに適用
- `sudo log stream`でSandbox動作を監視し、設定を最適化
- 他の防御層（ファイル権限、ネットワーク制限等）と組み合わせて多層防御を構築

# 参考文献

- [Chromium Sandbox (macOS) - GitHub](https://github.com/chromium/chromium/tree/main/sandbox/mac)
- [VS Code Security - Official Documentation](https://code.visualstudio.com/docs/editor/workspace-trust)
- [macOS Security and Privacy Guide](https://github.com/drduh/macOS-Security-and-Privacy-Guide)
- [Sandbox operations - Apple Developer (非公式逆引き)](https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf)

---

**更新履歴**
- 2025-11-03: 初版公開（macOS 14 Sonoma、Claude Code v0.8.0で動作確認）

**既知の制約**
- macOS 15以降では一部の動作変更の可能性がある
- Apple Silicon（M1/M2/M3）とIntelチップで動作確認済み
