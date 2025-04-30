python -m venv .venv
source .venv/bin/activate

pip install pre-commit
pre-commit --version

git init
pre-commit install
echo ".venv/" > .gitignore
pre-commit sample-config > .pre-commit-config.yaml

