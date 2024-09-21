## Super popular git commands

### outputs the name of remote
git remote

### Pull a remote branch to current branch
git pull origin BRANCH

e.g.
git pull origin main

### The pull command also has the prune option (--prune or -p) 
git pull -p

### To create and switch to a new branch in Git:
git checkout -b NEW_BRANCH_NAME

git checkout -b \<my_new_branch\> \<remote\>/\<branch_name\>

e.g. 
git checkout -b NEW_BRANCH_NAME origin/main

### To switch to a different branch
git switch BRANCH_NAME

### verify if you are working on that branch:
git branch

### Add changed files to staging
git add .

### git status command can be used to obtain a summary of which files have changes that are staged for the next commit.
git status 

### commit changes in staging area
git commit -m "Add Message"

### push this new branch to a remote repository
git push -u origin NEW_BRANCH_NAME

### Then you can create a pull request from github



## More
### if you are on main then merge the origin/main into main branch
git merge origin/main
