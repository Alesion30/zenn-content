- Apple Seatbeltとは
  - ファイル読み書きやネットワーク通信等を制限するSandbox
  - SBPL（Sandbox Profile Language）と呼ばれるファイルに、権限設定を記述し、`sandbox-exec` を用いて実行する
  - Apple的には非公式で、仕様も非公開
  - iOSアプリやMacアプリ・Chromium等で使われている。最近では、CodexやGemini・Claude Code・Cursor等でも使われている
    - 該当するコード（GitHub）を貼る
- Apple Seatbeltの記法
  - ファイル読み書き
  - ネットワーク通信
  - 正規表現指定
  - その他の制限
- ログ出力の方法
  - `sudo log stream --predicate 'sender == "Sandbox"' | grep deny`
  - ログを出しながら、SBPLファイルを調整すると良い
- Claude Codeでの利用例
  - Claude Codeにはsandbox機能がある
  - 筆者の環境では、sandbox機能を解除し、実行した例もあるため、自前でSBPLを用意して、Claude Codeを制限した方がセキュアである
  - .sbファイルの例を貼る
  - `sandbox-exec -f sandbox-macos-permissive-open.sb -D TARGET_DIR="$(pwd)" -D HOME_DIR="$HOME" claude`
  - devcontainerやsettings.jsonによる設定がClaude Codeの公式でサポート（紹介）されているが、それらと比較したメリット・デメリット
  - ただし、AI Agentを安全に使うには、多層の制限をかけることが重要と言われている
- そのほかのsandboxを提供する技術
  - SELinux、AppArmor、seccomp 等
  - Windows Sandbox
  - Docker

---

.sbの例

```sh:sandbox-macos-permissive-open.sb
;; sandbox-exec -f sandbox-macos-permissive-open.sb -D TARGET_DIR="$(pwd)" -D HOME_DIR="$HOME"
;; NOTE(log確認方法): `sudo log stream --predicate 'sender == "Sandbox"' | grep deny`

(version 1)

;; allow everything by default
(allow default)

;; ネットワークアクセス
(allow network-outbound)
(deny network-inbound)

;; Keychain アクセスを明示的に許可
(allow file-read*
    (subpath (string-append (param "HOME_DIR") "/Library/Keychains"))
    (literal "/Library/Keychains/System.keychain")
)
(allow file-write*
    (subpath (string-append (param "HOME_DIR") "/Library/Keychains"))
)

;; 読み込み権限
(deny file-read*
    ;; .env*ファイルの読み込みを明示的に拒否
    (regex #"\.env*$")
)
(allow file-read*)

;; 書き込み権限
(deny file-write*)
(allow file-write*
    (subpath (param "TARGET_DIR"))
    (regex (string-append "^" (param "HOME_DIR") "/.claude*"))
    (subpath (string-append (param "HOME_DIR") "/.npm"))

    ;; 一時ファイル関連
    (subpath "/tmp")
    (subpath "/private/tmp")
    (subpath "/var/folders")
    (subpath "/private/var/folders")
    (subpath (string-append (param "HOME_DIR") "/.cache"))
    (subpath (string-append (param "HOME_DIR") "/Library/Caches"))

    (subpath (string-append (param "HOME_DIR") "/.local"))
    (subpath (string-append (param "HOME_DIR") "/.zplug"))
    (literal "/dev/stdout")
    (literal "/dev/stderr")
    (literal "/dev/null")
    (literal "/dev/dtracehelper")
    (regex #"^/dev/tty*")
)
```
