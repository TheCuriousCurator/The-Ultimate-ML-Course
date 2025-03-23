
![Client-Server](https://raw.githubusercontent.com/TheCuriousCurator/The-Ultimate-ML-Course/main/images/git/git-client-server.png "Client-Server")

## Super popular git commands
`git init`

`git config --global user.name "The Curious Curator"`

`git config --global user.email "curious.curator.services@gmail.com"`


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


```
# If foo does not exist and origin/foo exists, try to create foo from origin/foo and then switch to foo:
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

## How to Revert to Last Commit?
Reverting to the last commit in Git is an important skill for developers who need to undo changes and return their project to a previous state. This article will guide you through various approaches to revert to the last commit, detailing each step to ensure you can effectively manage your Git repository.

Reverting to the last commit means discarding the changes made after the last commit and bringing your working directory back to the state it was in at that commit. This is useful when recent changes have introduced errors, and you need to return to a stable state. There are several ways to accomplish this in Git, each with its own use cases and benefits.

Approaches to Revert to Last Commit in Git are mentioned below:

### Using `git reset`
`git reset` is a powerful command used to undo changes. It can modify the index, the working directory, and the commit history.

## Check the commit history:
`git log --oneline`
### Identify the commit hash (e.g., `a1b2c3d`) you want to reset to.

## Hard reset to the last/previous commit
`git reset --hard HEAD^`
`git reset --hard a1b2c3d`

### Using `git revert`
`git revert` creates a new commit that undoes the changes from a previous commit.

## Revert the last commit
`git revert HEAD`

### Reverting to last commit might fail
- option 1: discard changes
- option 2: `git stash` (move current changes to stash). Use `git stash pop` to get back those changes. 

## Tagging a commit with a name

`git checkout  a1b2c3d`

`git tag v0.2.3`

Lets say now current master branch is a major release. We can communicate this to the community by using tag v1.0.0 by using the following commands.

`git checkout main`

`git tag v1.0.0`
