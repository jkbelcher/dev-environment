# Git shortcuts for zsh. git/install.sh copies this file to
# ~/.config/zsh/git-aliases.zsh and loads it from ~/.zshrc.
# To change them, edit this file and run git/install.sh again.

alias gs='git status'
alias gb='git branch'
alias gc='git checkout'
alias gcb='git checkout -b'
alias gd='git diff'
# One commit per line: full hash, date, subject
alias gl='git log --pretty=format:"%H %ad %s" --date=format:"%Y-%m-%d"'
alias gp='git pull'
alias gpu='git push -u'
alias grv='git remote -v'
