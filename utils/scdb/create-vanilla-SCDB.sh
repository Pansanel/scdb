#!/bin/sh
# This script creates a vanilla SCDB from QWG site.
# SCDB itself is download from SVN and the templates are located
# from the various Git repositories holding them.
# The cluster examples are then compiled.
#
# Written by Michel Jouvin <jouvin@lal.in2p3.fr>, 30/9/2013
#

# Variables describing repositories to fetch to build the new SCDB.
# For each repo xxx, the following variables must/may exist:
#  - xxx_git_repo: name of the Git repo (at git_url_root url)
#  - xxx_branch_pattern: a regexp to select the "branch" to fetch
#                        ("branch" is matched against the branch or tag
#                         according to xxx_use_tags)
#  - xxx_use_tags (optional): use list of existing tags rather than list of branches
#                             (D: use_tags_default)
#  - xxx_tags_ignore_pattern: ignore branch pattern when use_tags is true
#                             (incompatible with xxx_ignore_version)
#  - xxx_ignore_version (optional): retrieve all branches/tags even if a specific
#                                   version is requested (D: ignore_version_default)
#  - xxx_dest_dir: directory where to put the repo contents, under SCDB root
#                  (%BRANCH% is replaced by the "branch" name, %TAG% by the
#                   Quattor version specified in the tag)
#  - xxx_rename_master (optional): "branch name" to use if the branch is master

git_url_root=https://github.com/quattor
git_repo_list='core examples grid os standard monitoring'
use_tags_default=1
# Do not change the following defaults except if you know what you are doing...
ignore_version_default=0
tags_ignore_pattern_pattern=master

core_git_repo=template-library-core
core_branch_pattern='legacy|13\.1\.3|14\..*'
core_dest_dir=cfg/quattor/%TAG%
# With core repo, always checkout all tags matching core_branch_pattern,
# whatever is done for other repos.
core_use_tags=1
core_ignore_version=1
# Rename master branch from -core repo
# Set to an empty string or comment out to disable renaming
# Can be used for each repository but generally used only with -core
core_rename_master=14.2.1

examples_git_repo=template-library-examples
examples_branch_pattern=master
examples_dest_dir=cfg

grid_git_repo=template-library-grid
grid_branch_pattern=.*
grid_dest_dir=cfg/grid/%BRANCH%

os_git_repo=template-library-os
os_branch_pattern=.*
os_dest_dir=cfg/os/%BRANCH%

standard_git_repo=template-library-standard
standard_branch_pattern=master
standard_dest_dir=cfg/standard

monitoring_git_repo=template-library-monitoring
monitoring_branch_pattern=master
monitoring_dest_dir=cfg/standard/monitoring

# Other initializations
# If a branch name matches one of the pattern, it will be ignored
# HEAD added to workaround a bug in the release procedure when producing 14.5
ignore_branch_patterns='\.obsolete$ ^HEAD$'
git_clone_root=/tmp/quattor-template-library
scdb_dir=/tmp/scdb-vanilla
list_branches=0
remove_scdb=0
verbose=0
add_legacy=0
externals_root_url=https://svn.lal.in2p3.fr/LCG/QWG/External
scdb_external_list="ant panc scdb-ant-utils svnkit"
panc_version=panc-10.0
ant_version=apache-ant-1.7.1
scdb_ant_utils_version=scdb-ant-utils-9.0.2
svnkit_version=svnkit-1.3.5
# scdb source is typically a clone of GitHub scdb repo, switched to the appropriate
# version/branch. By default, the root of the clone is 2 level upper than the directory
# containing this script (util/scdb)
scdb_source="$(dirname $0)/../.."
if [ ! -e "${scdb_source}/quattor.build.xml" ]
then
  echo "$(basename $0) must be run from a scdb repository clone".
  exit 1
fi

usage () {
  echo "usage:  `basename $0` [-F] [--debug] [-d scdb_dir] [quattor_version]"
  echo ""
  echo "        -d scdb_dir : directory where to create SCDB."
  echo "                      (D: ${scdb_dir})"
  echo "        --debug : debug mode. Checkout rather than export templates"
  echo "        -F : remove scdb_dir if it already exists."
  echo "        -l : list available branches."
  echo ""
  exit 1
}

copy_scdb_external () {
  if [ -z "$1" ]
  then
    echo "Internal error: missing destination directory in copy_scdb_exernal()"
    exit 20
  fi
  if [ -z "$2" ]
  then
    echo "Internal error: missing external version in copy_scdb_exernal()"
    exit 20
  fi
  echo "Adding $1 version $2..."
  svn export ${externals_root_url}/$2 ${scdb_dir}/external/$1 > /dev/null
  if [ $? -ne 0 ]
  then
    echo "Error adding $1. Aborting..."
    exit 21
  fi
}

while [ -n "`echo $1 | grep '^-'`" ]
do
  case $1 in
  --add-legacy)
     add_legacy=1
     ;;

  -d)
    shift
    scdb_dir=$1
    ;;

  --debug)
    verbose=1
    ;;

  -l)
    list_branches=1
    ;;

  -F)
    remove_scdb=1
    ;;

  *)
    usage
    ;;
  esac
  shift
done

if [ -n "$1" ]
then
  quattor_version=$1
else
  quattor_version=
  echo "Temporary: quattor version to checkout is required"
  exit 1
fi

if [ ${add_legacy} -ne 1 ]
then
  ignore_branch_patterns="${ignore_branch_patterns} legacy$"
fi

# Check (or remove) the SCDB destination directory.
if [ -d ${scdb_dir} ] 
then
  if [ ${remove_scdb} -eq 0 ]
  then
    echo "Directory $scdb_dir already exists. Remove it or use -F"
    exit
  else
    echo "Removing ${scdb_dir}..."
    rm -Rf ${scdb_dir}
  fi
fi
mkdir -p ${scdb_dir}

# Check (or remove+create) if the destination directory for Git clones exists
if [ -d ${git_clone_root} ]
then
  if [ ${remove_scdb} -eq 0 ]
  then
    echo "Directory ${git_clone_root} already exists. Remove it or use -F"
    exit
  else
    echo "Removing ${git_clone_root}..."
    rm -Rf ${git_clone_root}
  fi
fi
mkdir ${git_clone_root}


echo "Creating vanilla SCDB from $scdb_source in $scdb_dir..."
cp -R ${scdb_source}/* ${scdb_dir}
if [ $? -ne 0 ]
then
  echo "Error creating vanilla SCDB. Aborting..."
  exit 1
fi
for external in ${scdb_external_list}
do
  tmp=$(echo ${external} | sed -e 's/-/_/g')
  external_version_variable=${tmp}_version
  copy_scdb_external ${external} ${!external_version_variable}
done

for repo in ${git_repo_list}
do
  repo_name_variable=${repo}_git_repo
  branch_variable=${repo}_branch_pattern
  dest_dir_variable=${repo}_dest_dir
  rename_master_variable=${repo}_rename_master
  use_tags_variable=${repo}_use_tags
  ignore_version_variable=${repo}_ignore_version
  tags_ignore_pattern_variable=${repo}_tags_ignore_pattern
  repo_name=${!repo_name_variable}
  repo_url=${git_url_root}/${repo_name}.git
  repo_dir=${git_clone_root}/${repo_name}
  branch_pattern=${!branch_variable}
  use_tags=${!use_tags_variable}
  if [ -z ${use_tags} ]
  then
    use_tags=${use_tags_default}
  fi
  ignore_version=${!ignore_version_variable}
  if [ -z ${ignore_version} ]
  then
    ignore_version=${ignore_version_default}
  fi
  tags_ignore_pattern=${!tags_ignore_pattern_variable}
  if [ -z ${tags_ignore_pattern} ]
  then
    if [ -z "$(echo ${branch_pattern} | egrep -- ${tags_ignore_pattern_pattern})" ]
    then
      tags_ignore_pattern=0
    else
      tags_ignore_pattern=1
    fi
  fi

  git_clone_dir=${git_clone_root}/${repo}
  if [ $?{!rename_master_variable} ]
  then
    master_dir_name=${!rename_master_variable}
  fi

  echo Cloning Git repository ${repo_url} in ${repo_dir}...
  export GIT_WORK_TREE=${repo_dir}
  export GIT_DIR=${repo_dir}/.git
  git clone --no-checkout ${repo_url} ${GIT_DIR}
  if [ $? -ne 0 ]
  then
    echo "Error cloning Git repository ${repo_url}"
    exit 10
  fi

  # In fact branch_pattern can be a regexp matched against existing branch names
  if [ ${use_tags} -eq 1 ]
  then
    if [ -n "${quattor_version}" -a ${ignore_version} -eq 0 ]
    then
      if [ ${tags_ignore_pattern} -eq 1 ]
      then
        branch_pattern="-${quattor_version}$"
      else
        branch_pattern="${branch_pattern}-${quattor_version}$"
      fi
    fi
    [ ${verbose} -eq 1 ] && echo "Using tags rather than branches for repository ${repo} (branch pattern=${branch_pattern})"
    branch_list=$(git tag | egrep -- "${branch_pattern}")
  else
    branch_list=$(git branch -r | egrep "origin/${branch_pattern}" | grep -v HEAD)
  fi
  [  ${verbose} -eq 1 -o ${list_branches} -eq 1 ] && echo -e "Branches/tags found in ${repo}:\n${branch_list}"
  [ ${list_branches} -eq 1 ] && continue
  
  for remote_branch in ${branch_list}
  do
    # Remove origin/ from the branch name
    branch=$(echo ${remote_branch} | sed -e 's#^.*origin/##')

    # branch_dir contains the branch name retrieved from the tag.
    # tag_dir contains the tag version derived from the tag name with the prefix 
    # (e.g. template-library-) removed. Define a non empty default value.
    tag_dir="undefined_tag"
    if [ "${branch}" = "master" -a $?{master_dir_name} ]
    then
      branch_dir=${master_dir_name}
    else
      branch_dir=$(echo ${branch} | sed -e 's%-\([0-9\.]\+\)\+\(-[0-Z]\+\)*$%%')
      tag_dir=$(echo ${branch} | sed -e "s%^.*${branch_dir}-%%")
      [ ${verbose} -eq 1 ] && echo branch_dir=$branch_dir, tag_dir=$tag_dir
    fi

    # Check if the branch should be ignored
    ignore_branch=0
    for ignore_pattern in ${ignore_branch_patterns}
    do
      [ ${verbose} -eq 1 ] && echo "Branch=${remote_branch}, ignore_pattern = >>${ignore_pattern}<<"
      if [ -n "$(echo ${branch_dir} | egrep -- ${ignore_pattern})" ]
      then
        echo "Branch ${remote_branch} ignored"
        ignore_branch=1
        break
      fi
    done
    if [ ${ignore_branch} -eq 1 ]
    then
      continue
    fi

    # Either %BRANCH% or %TAG% can be specified: no attempt to check that both are not use at the same time...
    dest_dir=${scdb_dir}/$(echo ${!dest_dir_variable} | sed -e "s#%BRANCH%#${branch_dir}#" | sed -e "s#%TAG%#${tag_dir}#")
    # os repository is a special case: '-spma' suffix must be removed to build the destination directory
    if [ ${repo} = "os" ]
    then
      dest_dir=$(echo ${dest_dir} | sed -e 's/-spma//')
    fi
    echo Copying Git branch ${branch} contents to ${dest_dir}...
    git checkout ${branch}
    mkdir -p ${dest_dir}
    cp -R ${repo_dir}/* ${dest_dir}
  done
done

echo "Compiling clusters/example..."
(cd ${scdb_dir}; external/ant/bin/ant --noconfig)
