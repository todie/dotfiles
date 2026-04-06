# completions.zsh — tool-specific completion setup

# Only load completion for tools that are actually installed.
has kubectl  && . <(kubectl completion zsh)  && compdef k=kubectl
has gh       && . <(gh completion -s zsh)    && compdef _gh gh
has glab     && . <(glab completion -s zsh)  && compdef _glab glab
has chezmoi  && . <(chezmoi completion zsh)  && compdef _chezmoi chezmoi
has op       && . <(op completion zsh)       && compdef _op op
has tsh      && . <(tsh --completion-script-zsh)      && compdef _tsh tsh
has tctl     && . <(tctl --completion-script-zsh)     && compdef _tctl tctl
has teleport && . <(teleport --completion-script-zsh) && compdef _teleport teleport
has tbot     && . <(tbot --completion-script-zsh)     && compdef _tbot tbot
has s3cmd    && compdef s3="s3cmd"
