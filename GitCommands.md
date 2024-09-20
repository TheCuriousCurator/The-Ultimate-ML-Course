git branch -M main

# To create and switch to a new branch in Git:
git checkout -b NEW_BRANCH_NAME
# verify if you are working on that branch:
git branch

git add .

# git status command can be used to obtain a summary of which files have changes that are staged for the next commit.
git status 


git commit -m "Add Message"

# push this new branch to a remote repository
git push -u origin <branch>
