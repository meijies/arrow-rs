#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
set -e

SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <version> <rc-num>"
  exit
fi

version=$1
rc=$2

tag=apache-arrow-${version}
tagrc=${tag}-rc${rc}

echo "Preparing source for tag ${tag}"

: ${release_hash=:`git rev-list $tag 2> /dev/null | head -n 1 `}

if [ -z "$release_hash" ]; then
  echo "Cannot continue: unknown git tag: $tag"
  exit
fi

echo "Using commit $release_hash"

tarball=${tag}.tar.gz

archive_name=tmp-apache-arrow
# be conservative and use the release hash, even though git produces the same
# archive (identical hashes) using the scm tag
git archive ${release_hash} --prefix ${archive_name}/ > ${archive_name}.tar.gz

dist_c_glib_tar_gz=c_glib.tar.gz
docker_image_name=apache-arrow/release-source
DEBUG=yes docker build -t ${docker_image_name} ${SOURCE_DIR}/source
docker \
  run \
  --rm \
  --interactive \
  --volume "$PWD":/host \
  ${docker_image_name} \
  /build.sh ${archive_name} ${dist_c_glib_tar_gz}

# replace c_glib/ by tar.gz generated by "make dist"
rm -rf ${tag}
git archive $release_hash --prefix ${tag}/ | tar xf -
rm -rf ${tag}/c_glib
tar xf ${dist_c_glib_tar_gz} -C ${tag}
rm -f ${dist_c_glib_tar_gz}

# Resolve all hard and symbolic links
rm -rf ${tag}.tmp
mv ${tag} ${tag}.tmp
cp -r -L ${tag}.tmp ${tag}
rm -rf ${tag}.tmp

# Create new tarball from modified source directory
tar czf ${tarball} ${tag}
rm -rf ${tag}

${SOURCE_DIR}/run-rat.sh ${tarball}

# sign the archive
gpg --armor --output ${tarball}.asc --detach-sig ${tarball}
shasum -a 256 $tarball > ${tarball}.sha256
shasum -a 512 $tarball > ${tarball}.sha512

# check out the arrow RC folder
svn co --depth=empty https://dist.apache.org/repos/dist/dev/arrow tmp

# add the release candidate for the tag
mkdir -p tmp/${tagrc}

# copy the rc tarball into the tmp dir
cp ${tarball}* tmp/${tagrc}

# commit to svn
svn add tmp/${tagrc}
svn ci -m "Apache Arrow ${version} RC${rc}" tmp/${tagrc}

# clean up
rm -rf tmp

echo "Success! The release candidate is available here:"
echo "  https://dist.apache.org/repos/dist/dev/arrow/${tagrc}"
echo ""
echo "Commit SHA1: ${release_hash}"
