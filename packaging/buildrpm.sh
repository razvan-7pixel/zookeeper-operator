#!/usr/bin/env bash
set -e

# =============
# This file is automatically generated from the templates in stackabletech/operator-templating
# DON'T MANUALLY EDIT THIS FILE
# =============


# This script creates an RPM package containing the binary created by this Cargo project.
# The script is not universally applicable, since it makes a few assumptions about the project structure:
#  1. The RPM scaffolding needs to be provided in `packaging/rpm`
#  2. The binary to be packaged needs to be created in target/release

# The script takes two arguments:
# 1. the name of the rust crate that should be built and which produces the binary that should be packaged
# 2. the name of the binary which this crate produces - this is also used as the name of the RPM package that this script
# creates - this parameter is optional and will default to 1. if not specified

# Check if one parameter was specified - we'll use this as the name parameter for all files
# This allows us to reuse the script across all operators
if [ -z $1 ]; then
  echo "This script requires the project name to be specified as the first parameter!"
  exit 1
fi

export WORKSPACE_NAME=$(basename $(pwd))

export PACKAGE_NAME=$1

# If a second parameter is specified this is used as the binary name, otherwise the first parameter
# is assumed to also specify the binary name
if [ -z $2 ]; then
  export BINARY_FILE_NAME=$PACKAGE_NAME
else
  export BINARY_FILE_NAME=$2
fi

BINARY_FILE_PATH=target/release/$BINARY_FILE_NAME

# The package description is parsed from the output of `cargo metadata` by using jq.
# We need to look up the package with a select statement to match the name from an array of packages
# The name is passed into jq as a jq variable, as no substitution would take place within the single
# quotes of the jq expression.
export PACKAGE_DESCRIPTION=$(~/.cargo/bin/cargo metadata --format-version 1| jq --arg NAME "$PACKAGE_NAME" '.packages[] | select(.name == $NAME) | .description')
if [ -z "$PACKAGE_DESCRIPTION" ]; then
  echo "Unable to parse package description from output of `cargo metadata`, cannot build RPM without this field!"
  exit 2
fi
echo

# Check that we are being called from the main directory and the release build process has been run
if [ ! -f $BINARY_FILE_PATH ]; then
    echo "Binary file not found at [$BINARY_FILE_PATH] - this script should be called from the root directory of the repository and 'cargo build --release' needs to have run before calling this script!"
    exit 3
fi

echo Cleaning up prior build attempts
rm -rf target/rpm

# Parse the version and release strings from the PKGID reported by Cargo
# This is in the form Path#Projectname:version, which we parse by repeated calls to awk with different separators
# This could most definitely be improved, but works for now
export VERSION_STRING=$(~/.cargo/bin/cargo pkgid --manifest-path rust/operator-binary/Cargo.toml  | awk -F'#' '{print $2}' |  awk -F':' '{print $2}')
echo version: ${VERSION_STRING}

export PACKAGE_VERSION=$(echo ${VERSION_STRING} | awk -F '-' '{print $1}')

# Any suffix like '-nightly' is split out into the release here, as - is not an allowed character in rpm versions
# The final release will look like 0.suffix or 0 if no suffix is specified.
export PACKAGE_RELEASE="0$(echo ${VERSION_STRING} | awk -F '-' '{ if ($2 != "") print "."$2;}')"

echo Defined workspace name: [${WORKSPACE_NAME}]
echo Defined package name: [${PACKAGE_NAME}]
echo Defined binary name: [${BINARY_FILE_NAME}]
echo Defined package version: [${PACKAGE_VERSION}]
echo Defined package release: [${PACKAGE_RELEASE}]
echo Defined package description: [${PACKAGE_DESCRIPTION}]

RPM_SCAFFOLDING_DIR=target/rpm/SOURCES/${BINARY_FILE_NAME}-${PACKAGE_VERSION}

echo Creating directory scaffolding for RPM : ${RPM_SCAFFOLDING_DIR}
mkdir -p ${RPM_SCAFFOLDING_DIR}

cp -r packaging/rpm/SOURCES/${BINARY_FILE_NAME}-VERSION/* ${RPM_SCAFFOLDING_DIR}/
cp -r packaging/rpm/SPECS target/rpm/

# Copy assets to the specified locations
echo Running copy_assets.py in $(pwd)

~/.cargo/bin/cargo metadata --format-version 1| $(dirname $0)/copy_assets.py ${PACKAGE_NAME} ${RPM_SCAFFOLDING_DIR}

echo Creating tar archive
pushd target/rpm/SOURCES
tar czvf ${BINARY_FILE_NAME}-${PACKAGE_VERSION}.tar.gz ${BINARY_FILE_NAME}-${PACKAGE_VERSION}
popd

echo Running rpmbuild
rpmbuild --define "_topdir `pwd`/target/rpm" -v -ba target/rpm/SPECS/${BINARY_FILE_NAME}.spec