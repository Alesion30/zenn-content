# Zenn Content

Zenn CLI を使用した技術記事・書籍の執筆・管理リポジトリ

## 環境要件

- Node.js 24
- direnv（推奨）

## セットアップ

```bash
# 依存関係のインストール
npm install

# ローカルプレビューサーバーの起動
npm run preview
```

## ディレクトリ構成

```
.
├── articles/      # 公開記事（Markdown）
├── books/         # 書籍（現在未使用）
└── notes/         # 下書き・メモ（Zenn非公開）
```

## コマンド

### 記事・書籍の管理

```bash
# ローカルプレビュー（ブラウザで http://localhost:8000 を開く）
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

## 参考リンク

- [📘 Zenn CLI の使い方](https://zenn.dev/zenn/articles/zenn-cli-guide)
- [📝 Zenn のマークダウン記法](https://zenn.dev/zenn/articles/markdown-guide)
