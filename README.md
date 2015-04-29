# rsync-deploy

> A server deploy script designed to quickly deploy a site with release versions while simultaneously limiting downtime due to rollbacks, failed deploys, and simultaneous deploys.

The script creates a cache on the server and updates it via `rsync`. After updating the cache, the build is copied into a numerically-ordered release folder then sym-linked a consistent directory for public access. This allows for rollbacks and recovery from failed deploys.

Throughout the entire deploy process, a lockfile is present to prevent simultaneous deploys.

I use `rsync-deploy` to deploy [chauncey.io](http://chauncey.io); it's worked great for me! Still, I'd like some more eyes on the code before I make this release a `v1` so if you have suggestions after trying out `rsync-deploy`, please submit an [issue](https://github.com/chauncey-garrett/rsync-deploy/issues "chauncey-garrett/rsync-deploy/issues") and I'll take it into consideration.

## Usage

In particular, notice the directory structure.

```
$ rsync-deploy --help

  Usage :  usage [options] [--]

  If using .rsync-deploy-rc, run the script from the same directory.

  Options:
  -h|--help       Display this message
  -v|--version    Display script version

  -i|--init       Initialize the deploy location
  -d|--deploy     Deploy the site
  -r|--rollback   Rollback to a previous version of the site
  -u|--unlock     Remove lockfile

  Directory structure:
  /var/www/chauncey.io/ # path_deploy_to
   |-  cache/           # dir_deploy_cache - rsync to save bandwidth
   |-  current          # a symlink to the current release in releases/
   |-  deploy.lock      # lock_file - help prevent multiple ongoing deploys
   |-  last_version     # contains the number of the last release
   '-  releases/        # dir_deploy_releases - one subdir per release
       |- 1/
       |- 2/
       |- 3/
       '- ...
```

Be sure to first run `rsync-deploy --init`, which will setup the site on your server!

## Dependencies

### Rsync

Of course! However, if you're on OS X you may wish to use [Bombich's rsync](http://bombich.com/kb/ccc4/credits) for improvements related to resource forks.

### ssh-key

For better security, an ssh-key is required for use of this script. If you don't already use one, see [this tutorial](https://help.github.com/articles/generating-ssh-keys/).

## Installation

### rsync-deploy.zsh

Add `rsync-deploy.zsh` to one of the following:

- To `/usr/local/bin`, or similar
- As a dependency in the root level of your project

Ensure it is executable:

```zsh
chmod +x rsync-deploy.zsh
```

### .rsync-deploy-rc

Customize then add `.rsync-deploy-rc` to the root level of any project you wish to deploy, **one file per project**. Every variable seen here is required. Set them accordingly.

```zsh
path_deploy_from="${PWD}"                     # read in the dir of the config file
path_deploy_to="/var/www/your-site-path-here" # important!
dir_deploy_cache="cache"
dir_local_stage="_builds/production"

username="ChaunceyGarrett"                    # important!
hostname="chauncey.io"                        # important!
port="22"                                     # important!
ssh_key="$HOME/.ssh/id_rsa"                   # important!

dir_deploy_releases="releases"
keep_releases="9"                             # important!

lock_file="deploy.lock"
```

## Like it?

If you have feature suggestions, please open an [issue](https://github.com/chauncey-garrett/rsync-deploy/issues "chauncey-garrett/rsync-deploy/issues"). If you have contributions, open a [pull request](https://github.com/chauncey-garrett/rsync-deploy/pulls "chauncey-garrett/rsync-deploy/pulls"). I appreciate any and all feedback.

## Author(s)

This script was inspired by Capistrano, Mina, and the like.

*The author(s) of this module should be contacted via the [issue tracker](https://github.com/chauncey-garrett/rsync-deploy/issues "chauncey-garrett/rsync-deploy/issues").*

  - [Chauncey Garrett](https://github.com/chauncey-garrett "chauncey-garrett")

[![](/img/tip.gif)](http://chauncey.io/reader-support/)
