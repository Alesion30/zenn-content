# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

このリポジトリは Zenn CLI を使用した技術記事・書籍の執筆・管理プロジェクトです。

- **記事**: `articles/` ディレクトリに Markdown ファイルとして配置
- **書籍**: `books/` ディレクトリに配置（現在は未使用）
- **下書き・メモ**: `notes/` ディレクトリに配置（Zenn 公開対象外）

## コンテンツ構造

### 記事ファイル（articles/*.md）

各記事は以下のフロントマターを持ちます：

```yaml
---
title: "記事タイトル"
emoji: "😎"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["react", "typescript", "vite"] # 技術タグ
published: true # true: 公開 / false: 下書き
---
```

## 開発コマンド

### 記事・書籍の管理

```bash
# ローカルプレビュー（ブラウザで確認）
npm run preview

# 新規記事作成
npm run new:article

# 新規書籍作成
npm run new:book

# 記事一覧表示
npm run list:article

# 書籍一覧表示
npm run list:book
```

### Lint（textlint）

```bash
# 記事の校正
npm run lint:article

# 書籍の校正
npm run lint:book
```

textlint の設定は `.textlintrc` で管理され、以下のルールセットを使用：
- `preset-japanese`: 日本語の基本ルール
- `preset-ja-technical-writing`: 技術文書向けルール
- `preset-ja-spacing`: スペーシングルール
- `spellcheck-tech-word`: 技術用語のスペルチェック

コメントフィルター（`textlint-filter-rule-comments`）が有効なため、`<!-- textlint-disable -->` と `<!-- textlint-enable -->` でルールを部分的に無効化できます。

## 環境要件

- Node.js 24 を使用（`package.json` の `engines` フィールドで指定）
- direnv を使用（`.envrc` で環境設定）

## 注意事項

- 記事ファイル名は Zenn が自動生成するランダムな slug（例: `132483d3fb6949.md`）を使用
- `notes/` ディレクトリは Zenn に公開されないため、下書きやメモの保管場所として使用可能
- このリポジトリはプライベート（`package.json` で `"private": true` 設定）
