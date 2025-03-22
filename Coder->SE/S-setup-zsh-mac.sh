# install Homebrew (brew) if it isn't already present
which brew || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
 
# update brew so it will install the most up-to-date versions of packages
brew update
 
# try to install sed, git, and zsh if they aren't already present
# Note: sed is a command for editing text files, we will use it further down
# to configure the ~/.zshrc file
which sed || brew install sed || echo "mac: could not install sed"
which zsh || brew install zsh || echo "mac: could not install zsh"
# to install git, 
 
 
# install OhMyZSH and configure it with some nice settings
[ -d ~/.oh-my-zsh ] || sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)
sed -i "" 's/^ZSH_THEME=".\+"/ZSH_THEME=\"bira\"/g' "$HOME/.zshrc"
exec "$HOME/.zshrc"
 
# install plugin: zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
 
# install plugin: zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
 
# enable the two above plugins as well as some of the default plugins
sed -i "" 's/\(^plugins=([^)]*\)/\1 python pip pyenv virtualenv web-search zsh-autosuggestions zsh-syntax-highlighting/' "$HOME/.zshrc"
 
# set the ZSH_THEME to "bira"
sed -i "" 's/_THEME=\".*\"/_THEME=\"bira\"/g' "$HOME/.zshrc"