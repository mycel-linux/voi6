# ~/.bashrc — interactive bash config for Voi6.
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'

PS1='[\[\e[1;34m\]\u@\h\[\e[0m\] \W]\$ '

# Voi6 greeting (your ASCII logo lives at /usr/share/voi6/voi6.txt).
if command -v fastfetch >/dev/null 2>&1; then
    fastfetch --config /etc/fastfetch/config.jsonc 2>/dev/null
fi
