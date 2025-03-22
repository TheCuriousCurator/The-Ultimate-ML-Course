# create a virtual environment 
# in a folder called "./venv/"
python -m venv ./venv/
 
# activate the virtual environment 
# so that "pip install ..." lands 
# packages into "./venv/lib/site-packages/" 
# and python programs executed with
# "python ./path/to/some/script.py" 
# evaluates "import" statements using 
# the packages in the 
# "./venv/lib/site-packages/" folder
source ./venv/bin/activate   # or ". ./venv/bin/activate"
 
# deactivate the virtual environment 
# to stop the behaviors caused 
# by activating a venv
deactivate

# /lib/python3.11/site-packages
python -m venv ./venv/
# python ~/.pyenv/versions/3.11.2/lib/python3.11/venv.py ./venv/
source ./venv/bin/activate