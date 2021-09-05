#!/bin/bash

#! v - select one of the recently edited files in vim
# A modern rewrite of https://github.com/rupa/v

: ${XDG_CACHE_HOME:=~/.cache}
: ${CACHE_DIR:=$XDG_CACHE_HOME/v}
[[ ! -d $CACHE_DIR ]] && mkdir -p "$CACHE_DIR"
: ${XDG_CONFIG_HOME:=~/.config}
: ${CONFIG_DIR:=$XDG_CONFIG_HOME/v}
[[ ! -d $CONFIG_DIR ]] && mkdir -p "$CONFIG_DIR"
# We allow the user to set the editor
: ${EDITOR:=vi}
# But we also need to query vim
: ${VI:=vi}

BOOKMARKS="${CONFIG_DIR}/dirs"
HISTORY_FILE="$CACHE_DIR/history"

HELP_FILE="$CONFIG_DIR/help"
[[ ! -e $HELP_FILE ]] && cat <<-EOF > "$HELP_FILE"
?: help
ctrl-e: files            ctrl-d: directories
ctrl-g: git's files      ctrl-s: git's changed files
ctrl-y: locate's files   ctrl-m: select
ctrl-p: up               ctrl-n: down
ctrl-f: preview-down     ctrl-b: preview-up
ctrl-v: vim              ctrl-o: original query

Search syntax
  foo     Fuzzy match (default)
  'foo    Exact match
  ^foo    Prefix exact match
  !foo    Inverse exact match
  !^foo   Inverse prefix exact match
  bar$    Suffix exact match
  !bar$   Inverse suffix exact match
  ^core go$ | rb$ | py$   Or operator
EOF

function v {
  local files=()
  local file
  local in_cwd=0
  local deleted=0
  local list_files=0

  local usage="${FUNCNAME[0]} [-a|-c|-l] [terms]"
  while getopts achlv opt; do
    case "$opt" in
      a) deleted=1;;
      c) in_cwd=1;;
      l) list_files=1;;
      h) echo >&2 "$usage"; return 0;;
    esac
  done
  shift "$((OPTIND-1))"   # Discard the options and sentinel --

  while read -r -d $'\0' file; do
    if (( in_cwd == 1 )) && [[ $file != ${PWD}* ]]; then
      continue
    fi

    [[ $file = *@(COMMIT_EDITMSG|/dev/null)* ]] && continue

    if (( deleted == 1 )) || [[ -e $file ]]; then
      files+=( "$file" )
    fi
  done < <(
    printf '%s\0' "$PWD"
    vim-fru -z
    git ls-files -z 2>/dev/null
  )

  if (( list_files == 1 )); then
    printf '%s\n' "${files[@]}" | tac
    exit 0
  fi

  git_status='
    git status --porcelain --no-column  --find-renames \
        --ignore-submodules=none 2>/dev/null | \
      sed -r  -e "s/^\s*[a-z?!]+\s+//i" \
        -e "s/^[a-z]+\s+->\s+//i"
  '

  # display the fzf/bat selection/preview
  local item=$(
    printf '%s\n' "${files[@]}" |
      git_status="$git_status" \
      fzf --ansi --cycle --no-mouse \
        --header 'Select to edit; ? for help' \
        --query "$*" \
        --color dark --inline-info --info inline \
        --border rounded --pointer '▶' --marker '✓' --prompt '$ ' \
        --bind 'ctrl-b:preview-page-up' \
        --bind 'ctrl-d:reload(find . -type d)' \
        --bind 'ctrl-e:reload(find . -type f)' \
        --bind 'ctrl-f:preview-page-down' \
        --bind 'ctrl-y:reload(
            locate -A {q} -i -L -p -r --regextype posix-extended
          )' \
        --bind 'ctrl-g:reload(git ls-files)' \
        --bind 'ctrl-i:reload(projects-list)' \
        --bind 'ctrl-u:reload(cwds-list)' \
        --bind 'ctrl-n:down' \
        --bind 'ctrl-o:reload(
            pwd
            cat $XDG_CACHE_HOME/dir-selected
            eval "$git_status"
            git ls-files
            dirs -l -p
            git rev-parse --show-toplevel
            cat "$BOOKMARKS"
            sed -r "s@^file://@@" ~/.gtk-bookmarks
            cwds-list
            projects-list
          )' \
        --bind 'ctrl-p:up' \
        --bind "ctrl-r:reload('$0' -l {q})" \
        --bind 'ctrl-s:reload(eval "$git_status")' \
        --bind 'ctrl-v:execute(/usr/bin/vi . < /dev/tty > /dev/tty 2>&1)' \
        --bind 'ctrl-z:ignore' \
        --bind "?:execute(less '${HELP_FILE}' < /dev/tty > /dev/tty 2>&1)" \
        --history "$HISTORY_FILE" \
        --preview '
            item="{}"

            [[ $item == *"	"* ]] && item="${item%%	*}"
            [[ $item == '"\'"'* ]] && item="${item#'"\'"'}"
            [[ $item == *'"\'"' ]] && item="${item%'"\'"'}"
            [[ $item == ~* ]] && item="${item/~\//$HOME/}"

            if [[ -r "$item" ]]; then
              if [[ -f "$item" ]]; then
                bat -f --style=full --line-range :300 "$item" || cat "$item";
              elif [[ -d "$item" ]]; then
                if (
                  cd "$item" && git rev-parse --is-inside-work-tree &>/dev/null
                ); then
                ( cd "$item";
                  git remote -v; echo;
                  git -c color.status=always status; echo;
                  git -c color.branch=always branch -alrv;
                )
                else
                  ( tree -C -L 2 "$item" | less ) ||  ls -l "$item";
                fi
                echo; stat -L "$item"
              fi
              exit 0
            fi;
            stat -L "$item"
          ' \
        --preview-window '~3:+{2}+3/2'
  )

  [[ $item == ~* ]] && item="${item/~\//$HOME/}"
  if [[ -e $item ]]; then
    "$EDITOR" "$item"; return $?
  fi
}

# delegate execution to the functions above
"${0##*/}" "$@"
