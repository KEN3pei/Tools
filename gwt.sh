#!/usr/bin/env zsh
# gwt - git worktree switcher
# 使い方: gwt [サブコマンド]
#   gwt          : worktreeをインタラクティブに選択してcdする
#   gwt list     : worktree一覧表示
#   gwt add <branch> [path] : worktreeを追加
#   gwt rm [path]           : worktreeを削除（インタラクティブ選択可）
#   gwt prune               : 不要なworktreeを削除

# ==============================
# ユーティリティ
# ==============================

_gwt_is_git_repo() {
  git rev-parse --git-dir &>/dev/null
}

# worktree一覧を "パス | ブランチ | HEAD" 形式で取得
_gwt_list_worktrees() {
  git worktree list --porcelain 2>/dev/null | /usr/bin/awk '
    /^worktree / { path = substr($0, 10) }
    /^branch /   { branch = substr($0, 8); gsub("refs/heads/", "", branch) }
    /^HEAD /     { head = substr($0, 6, 8) }
    /^$/         {
      if (path != "") {
        printf "%-50s  %-30s  %s\n", path, branch, head
        path=""; branch="(detached)"; head=""
      }
    }
    END {
      if (path != "") printf "%-50s  %-30s  %s\n", path, branch, head
    }
  '
}

# fzfで選択、なければ番号メニュー
_gwt_select() {
  local prompt="${1:-worktree> }"
  local input
  input="$(cat)"

  if [[ -z "$input" ]]; then
    echo "worktreeが見つかりません" >&2
    return 1
  fi

  if command -v fzf &>/dev/null; then
    echo "$input" | fzf --prompt="$prompt" --height=40% --border --ansi
  else
    # fzfがない場合は番号メニュー
    local lines=()
    while IFS= read -r line; do
      lines+=("$line")
    done <<< "$input"

    echo "" >&2
    for i in "${!lines[@]}"; do
      printf "  [%d] %s\n" "$((i+1))" "${lines[$i]}" >&2
    done
    echo "" >&2
    printf "番号を選択 (1-%d, q=キャンセル): " "${#lines[@]}" >&2

    local choice
    read -r choice </dev/tty
    [[ "$choice" == "q" || -z "$choice" ]] && return 1

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#lines[@]} )); then
      echo "${lines[$((choice-1))]}"
    else
      echo "無効な選択です" >&2
      return 1
    fi
  fi
}

# ==============================
# サブコマンド
# ==============================

_gwt_cd() {
  _gwt_is_git_repo || { echo "エラー: gitリポジトリ内で実行してください" >&2; return 1; }

  local selected
  selected=$(_gwt_list_worktrees | _gwt_select "worktree> ")
  [[ -z "$selected" ]] && return 1

  local path
  path=$(echo "$selected" | /usr/bin/awk '{print $1}')

  if [[ -d "$path" ]]; then
    cd "$path" || return 1
    echo "移動先: $path"
  else
    echo "エラー: ディレクトリが存在しません: $path" >&2
    return 1
  fi
}

_gwt_list() {
  _gwt_is_git_repo || { echo "エラー: gitリポジトリ内で実行してください" >&2; return 1; }

  local current
  current=$(git rev-parse --show-toplevel 2>/dev/null)

  echo ""
  printf "  %-50s  %-30s  %s\n" "パス" "ブランチ" "HEAD"
  printf "  %s\n" "$(printf '─%.0s' {1..90})"

  local wt_lines wt_path
  wt_lines=$(_gwt_list_worktrees)
  while IFS= read -r line; do
    wt_path=$(echo "$line" | /usr/bin/awk '{print $1}')
    if [[ "$wt_path" == "$current" ]]; then
      printf "  \033[1;32m* %s\033[0m\n" "$line"
    else
      printf "    %s\n" "$line"
    fi
  done <<< "$wt_lines"
  echo ""
}

_gwt_add() {
  _gwt_is_git_repo || { echo "エラー: gitリポジトリ内で実行してください" >&2; return 1; }

  local branch="$1"
  local path="$2"

  if [[ -z "$branch" ]]; then
    echo "使い方: gwt add <branch> [path]" >&2
    return 1
  fi

  if [[ -z "$path" ]]; then
    # デフォルトパス: リポジトリルートの親ディレクトリに <repo>-<branch> で作成
    local root
    root=$(git rev-parse --show-toplevel)
    local repo_name
    repo_name=$(basename "$root")
    path="${root%/*}/${repo_name}-${branch//\//-}"
  fi

  git worktree add "$path" "$branch" && echo "worktree作成: $path (ブランチ: $branch)"
}

_gwt_rm() {
  _gwt_is_git_repo || { echo "エラー: gitリポジトリ内で実行してください" >&2; return 1; }

  local path="$1"

  if [[ -z "$path" ]]; then
    # インタラクティブ選択（メインworktreeは除外）
    local main_path
    main_path=$(git worktree list --porcelain | /usr/bin/awk 'NR==1{print $2}')

    local selected
    selected=$(_gwt_list_worktrees | grep -v "^$main_path" | _gwt_select "削除するworktree> ")
    [[ -z "$selected" ]] && return 1

    path=$(echo "$selected" | /usr/bin/awk '{print $1}')
  fi

  echo "削除: $path"
  printf "本当に削除しますか？ [y/N]: "
  local confirm
  read -r confirm </dev/tty
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    git worktree remove "$path" && echo "削除完了: $path"
  else
    echo "キャンセルしました"
  fi
}

_gwt_prune() {
  _gwt_is_git_repo || { echo "エラー: gitリポジトリ内で実行してください" >&2; return 1; }
  git worktree prune -v && echo "pruneが完了しました"
}

# ==============================
# メインエントリポイント (shell function として使用)
# ==============================

gwt() {
  local cmd="${1:-}"

  case "$cmd" in
    ""|switch|sw)
      _gwt_cd
      ;;
    list|ls|l)
      _gwt_list
      ;;
    add|a)
      shift
      _gwt_add "$@"
      ;;
    rm|remove)
      shift
      _gwt_rm "$@"
      ;;
    prune)
      _gwt_prune
      ;;
    help|-h|--help)
      cat <<'EOF'

  gwt - git worktree switcher

  使い方:
    gwt              worktreeをインタラクティブに選択してcd
    gwt list         worktree一覧を表示
    gwt add <branch> [path]  新しいworktreeを追加
    gwt rm [path]    worktreeを削除（引数省略でインタラクティブ選択）
    gwt prune        不要なworktreeの参照を削除
    gwt help         このヘルプを表示

  ヒント: fzfをインストールするとファジー検索が使えます
    brew install fzf

EOF
      ;;
    *)
      echo "不明なサブコマンド: $cmd  (gwt help でヘルプ表示)" >&2
      return 1
      ;;
  esac
}
