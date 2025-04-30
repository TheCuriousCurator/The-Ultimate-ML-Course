# https://docs.astral.sh/uv/concepts/projects/init/#applications
# https://docs.astral.sh/uv/concepts/projects/
# https://docs.astral.sh/uv/concepts/projects/init/#packages
uv init example-app
tree example-app


uv init --package example-pkg
tree example-pkg

uv add pandas duckdb plotly streamlit
uv add scikit-learn
uv add openai
uv add --dev pytest
uv add --dev pytest-cov
uv add --dev black
uv add --dev flake8
uv add --dev mypy
uv add --dev pre-commit
uv add --dev isort
uv add --dev coverage
uv add --dev pytest-benchmark

uv remove openai
uv remove --dev pytest-benchmark

# similar to pip install -r requirements.txt
uv sync

uv run streamlit run app.py
uv run python hello.py

uv tool run ruff
uv tool run black
uv tool run cowsay --text hello
uv tool run black --check

uv pip install ....
