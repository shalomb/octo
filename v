#!/bin/bash

#! vi - launch last related-in-flow files in vi
function vi {
  if [[ -n $@ ]]; then
    local _PATH="$PATH"
    unset PATH
    source /etc/profile &>/dev/null
    command vi "$@"
    PATH="$_PATH"
  else
    if [[ -n ${_git_args[@]} ]]; then
      command vi "${_git_args[@]}"
    else
      v
    fi
  fi
}

#! locate-viminfo - return the path of viminfo that we cached
function locate-viminfo {
  local tmpfile=$(mktemp)
  local v_viminfo="${XDG_CACHE_HOME:-~/.cache}/v.viminfo"

  # our file is a symlink to the real viminfo
  if [[ -e $v_viminfo ]]; then
    echo "$v_viminfo"
    return 0
  fi

  # ask vim to tell us where the viminfo is
  for line in "redir! > $tmpfile" "set viminfo" "redir END" "quit"; do
    echo ":$line"
  done > "$tmpfile"
  command "${EDITOR:-vi}" \
    -v -R -m -M -n --noplugin -i NONE \
    -s "$tmpfile" /dev/null &>/dev/null

  # parse the viminfo part
  local viminfo=$(grep -oiP '(?<=,n).+' "$tmpfile")
  viminfo="${viminfo/~\//$HOME/}"
  rm -f "$tmpfile"

  if [[ ! -f $viminfo ]]; then
    echo >&2 "viminfo '$viminfo' missing or inaccessible?"
    return 1
  fi

  # cache the viminfo location
  ln -sf "$viminfo" "$v_viminfo"
  echo "$v_viminfo"
  return 0
}

#! v - select one of the recently edited files in vim
# A modern rewrite of https://github.com/rupa/v
function v {
  local viminfo=$(locate-viminfo)
  local files=()
  local v_hist_file=~/.cache/v.history
  local file
  local in_cwd=0
  local deleted=0
  local list_files=0

  local usage="$(basename ${FUNCNAME[0]}) [-a|-c] [terms]"
  while getopts achlv opt; do
    case "$opt" in
      a) deleted=1;;
      c) in_cwd=1;;
      l) list_files=1;;
      h) echo >&2 "$usage"; return 0;;
    esac
  done
  shift "$((OPTIND-1))"   # Discard the options and sentinel --

  # parse the viminfo for file locations
  while IFS=" " read -r line; do
    [[ ${line:0:1} = ">" ]] || continue
    file=${line:2}
    file="${file/~\//$HOME/}"

    if (( in_cwd == 1 )) && [[ $file != ${PWD}* ]]; then
      continue
    fi

    [[ $file = *@(COMMIT_EDITMSG|/dev/null)* ]] && continue

    if (( deleted == 1 )) || [[ -e $file ]]; then
      files+=( "$file" )
    fi
  done < "$viminfo"

  if (( list_files == 1 )); then
    printf '%s\n' "${files[@]}" | tac
    exit 0
  fi

  # display the fzf/bat selection/preview
  [[ ! -e $v_hist_file ]] && touch "$v_hist_file"
  mkdir -p ~/.config/v/
  cat <<-EOF > ~/.config/v/help
?: help
ctrl-e: files          ctrl-d: directories
ctrl-e: vim            ctrl-r: reload
ctrl-p: up             ctrl-n: down
ctrl-f: preview-down   ctrl-b: preview-up
ctrl-y: locate         ctrl-m: select

Search syntax
  'wild    Exact match
  ^music   Prefix-exact-match
  .mp3$    Suffix-exact-match
  !fire    Inverse-exact-match
  !^music  Inverse-prefix-exact-match
  !.mp3$   Inverse-suffix-exact-match
  ^core go$ | rb$ | py$   Or operator
EOF

  file=$(
    printf '%s\n' "${files[@]}" |
      fzf --ansi --cycle --no-mouse --inline-info --color dark --info inline \
        --header 'Select to edit; ? for help' \
        --border rounded --pointer '▶' --marker '✓' --prompt '$ ' \
        --bind 'ctrl-b:preview-page-up' \
        --bind 'ctrl-d:reload(find . -type d)' \
        --bind 'ctrl-e:reload(find . -type f)' \
        --bind 'ctrl-f:preview-page-down' \
        --bind 'ctrl-y:reload(locate /)' \
        --bind 'ctrl-g:reload(git ls-files)' \
        --bind 'ctrl-n:down' \
        --bind 'ctrl-h:backward-char' \
        --bind 'ctrl-p:up' \
        --bind "ctrl-r:reload('$0' "$@")" \
        --bind 'ctrl-v:execute(/usr/bin/vi . < /dev/tty > /dev/tty 2>&1)' \
        --bind 'ctrl-z:ignore' \
        --bind '?:execute(less ~/.config/v/help < /dev/tty > /dev/tty 2>&1)' \
        --history "$v_hist_file" \
        --preview '
            if [[ -r {} ]]; then
              if [[ -f {} ]]; then
                bat -f --style=full --line-range :300 {} || cat {};
              elif [[ -d {} ]]; then
                ( tree -C -L 2 {} | less ) ||  ls -l {};
                echo;stat -L {}
              fi
              exit 0
            fi;
            stat -L {}
          ' \
        --preview-window '~3:+{2}+3/2'
  )

  if [[ -e $file ]]; then
    echo "$file" >> "$v_hist_file"
    command "${EDITOR:-vi}" "$file"
  fi
}

# delegate execution to the functions above
"${0##*/}" "$@"
