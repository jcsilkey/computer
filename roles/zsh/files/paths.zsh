typeset -gU cdpath fpath mailpath manpath path
typeset -gUT INFOPATH infopath

fpath=(
  $ZSH_CONFIG/completions
  $ZSH_CONFIG/functions
  /usr/local/share/zsh/site-functions
  $fpath
)

manpath=(
  /opt/local/share/man
  /usr/local/share/man
  /usr/share/man
  $manpath
)

infopath=(
  /opt/local/share/info
  /usr/local/share/info
  /usr/share/info
  $infopath
)

path=(
  ~/bin
  ~/.bin
  /opt/local/{bin,sbin}
  /usr/local/{bin,sbin}
  /usr/{bin,sbin}
  /{bin,sbin}
  $path
  ~/.composer/vendor/bin
)
