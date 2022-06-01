.PHONY: no_target
no_target:
	@exit 1 ## I'd like to notice to fail if user call 'make' without any target.

SRC_ARTICLE_DIR := articles
SRC_BOOK_DIR := books

TEXT_LINT_TARGET := \
	articles \
	books

##########################################
# Self-documentize utility
##########################################
.PHONY: help
help: ## 📄 Show documentation
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""


##########################################
# Bootstrap
##########################################
.PHONY: init
init: ## 🔨 Install dependencies
	yarn


##########################################
# Development
##########################################
.PHONY: preview
preview: ## 🖥  Preview content in the browser
	yarn preview


##########################################
# Create
##########################################
.PHONY: new_article
new_article: ## 📝 Create new article
	yarn new:article

.PHONY: new_book
new_book: ## 📕 Create new book
	yarn new:book


##########################################
# Lint
##########################################
.PHONY: textlint
textlint: ## 🚨 Run textlint for All
	$(MAKE) $(addprefix textlint_, $(TEXT_LINT_TARGET))

.PHONY: textlint_articles
textlint_articles: ## 🚨 Run textlint for Articles
	yarn lint:article

.PHONY: textlint_books
textlint_books: ## 🚨 Run textlint for Books
	yarn lint:book


##########################################
# Code format
##########################################
.PHONY: fmt
fmt: ## ✨ Format code for All
	$(MAKE) $(addprefix fmt_, $(TEXT_LINT_TARGET))

.PHONY: fmt_articles
fmt_articles: ## ✨ Format code for Articles
	yarn lint:article --fix

.PHONY: fmt_books
fmt_books: ## ✨ Format code for Books
	yarn lint:book --fix
