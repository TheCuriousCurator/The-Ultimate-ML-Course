## Super popular git commands

```
git fetch origin     // origin is the remote name you are targeting
git branch -a
git branch
git checkout -b test-remote-clone origin/test-remote-clone
git add <{fileNames}>         // specify all file names that you need to commit
git commit -m "add new file" // you can give relevant commit message here
git push                    // Here we no need to specify the remote branch 
                               name, because git automatically sets the local 
                               branch to track the remote branch 
```
### outputs the name of remote
`git remote`

### Pull a remote branch to current branch
`git pull origin BRANCH`

e.g.
`git pull origin main`

### The pull command also has the prune option (--prune or -p) 
`git pull -p`

### To create and switch to a new branch in Git:
`git checkout -b NEW_BRANCH_NAME`

`git checkout -b <my_new_branch> <remote>/<branch_name>`

e.g. 
`git checkout -b NEW_BRANCH_NAME origin/main`

### To switch to a different branch
`git switch BRANCH_NAME`

If foo does not exist and origin/foo exists, try to create foo from origin/foo and then switch to foo:

```
git switch -c foo origin/foo
# or simply
git switch foo
```

### verify if you are working on that branch:
`git branch`

### Add changed files to staging
`git add .`

### git status command can be used to obtain a summary of which files have changes that are staged for the next commit.
`git status`

### commit changes in staging area
`git commit -m "Add Message"`

### push this new branch to a remote repository
`git push -u origin NEW_BRANCH_NAME`

### Then you can create a pull request from github

### delete a branch
`git branch --delete <branchname>`

## More
### if you are on main then merge the origin/main into main branch
`git merge origin/main`
