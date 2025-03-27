# update apt-get so it will install the most up-to-date versions of packages
apt-get update
 
# try to install sed, git, and zsh if they aren't already present
# Note: sed is a command for editing text files, we will use it further down
# to configure the ~/.zshrc file
which sed || sudo apt-get install -y sed || echo "linux: could not install sed"
which zsh || sudo apt-get install -y zsh || echo "linux: could not install zsh"
which git \
    || sudo add-apt-repository ppa:git-core/ppa \
    && sudo apt-get update \
    && sudo apt-get install -y git \
    || echo "mac: could not install git"
 
# install OhMyZSH if it isn't already installed
[ -d ~/.oh-my-zsh ] || sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
 
# plugin: zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
 
# plugin: zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# plugin: fzf for fuzzy match for auto-completion
git clone --depth 1 https://github.com/unixorn/fzf-zsh-plugin.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-zsh-plugin

# plugin: fzf-tab for zsh default completion
git clone https://github.com/Aloxaf/fzf-tab ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab

# add these two plugins and enable some of the default ones
sed -i 's/\(^plugins=([^)]*\)/\1 git web-search python pyenv virtualenv pip fzf-tab zsh-autosuggestions zsh-syntax-highlighting fzf-zsh-plugin/' "$HOME/.zshrc"
 
# set the ZSH_THEME to "bira"
sed -i 's/_THEME=\".*\"/_THEME=\"bira\"/g' "$HOME/.zshrc"

echo "source ~/.oh-my-zsh/custom/plugins/fzf-zsh-plugin/fzf-zsh-plugin.plugin.zsh" >> ~/.zshrc

echo "source ~/.oh-my-zsh/custom/plugins/fzf-tab/fzf-tab.plugin.zsh" >> ~/.zshrc

conda init zsh
zsh
conda activate ~/conda_env/pytorch_GPU_3.9/

