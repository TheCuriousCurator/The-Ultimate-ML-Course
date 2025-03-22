
### Install pyenv
`curl -fsSL https://pyenv.run | bash`

### In ~/.zshrc copy:

`export PYENV_ROOT="$HOME/.pyenv"`

`export PATH="$PYENV_ROOT/bin:$PATH"`

`eval "$(pyenv init --path)"`

### Common commands:
#### To see all versions installed in the system
`pyenv versions`

#### To see total number of versions available
`pyenv install --list | wc -l`

#### To list all versions
`pyenv install --list`

#### To use 3.11 version
`pyenv shell 3.11`

#### To make 3.11 global version (even after shell restart)
`pyenv global 3.11`

#### To install version 3.11 (from a long long list which can be seen by `pyenv install --list`)
`pyenv install 3.11`

#### If your build fails with command `pyenv install 3.11` install the following commands in Build Environment

### Build Environment
Read https://github.com/pyenv/pyenv/wiki#suggested-build-environment

`sudo apt-get update;` 

`sudo apt-get install build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev;`

`sudo apt-get install -y make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev python3-openssl git openssl`


### install python & pylance pluging in VS Code.