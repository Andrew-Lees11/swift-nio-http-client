#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftNIOHTTPClient open source project
##
## Copyright (c) 2018-2019 Swift Server Working Group and the SwiftNIOHTTPClient project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftNIOHTTPClient project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -e

my_path="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
root_path="$my_path/.."
version=$(git describe --abbrev=0 --tags || echo "master")
modules=(NIOHTTPClient)

if [[ "$(uname -s)" == "Linux" ]]; then
  # build code if required
  if [[ ! -d "$root_path/.build/x86_64-unknown-linux" ]]; then
    swift build
  fi
  # setup source-kitten if required
  source_kitten_source_path="$root_path/.SourceKitten"
  if [[ ! -d "$source_kitten_source_path" ]]; then
    git clone https://github.com/jpsim/SourceKitten.git "$source_kitten_source_path"
  fi
  source_kitten_path="$source_kitten_source_path/.build/x86_64-unknown-linux/debug"
  if [[ ! -d "$source_kitten_path" ]]; then
    rm -rf "$source_kitten_source_path/.swift-version"
    cd "$source_kitten_source_path" && swift build && cd "$root_path"
  fi
  # generate
  mkdir -p "$root_path/.build/sourcekitten"
  for module in "${modules[@]}"; do
    if [[ ! -f "$root_path/.build/sourcekitten/$module.json" ]]; then
      "$source_kitten_path/sourcekitten" doc --spm-module $module > "$root_path/.build/sourcekitten/$module.json"
    fi
  done
fi

[[ -d docs/$version ]] || mkdir -p docs/$version
[[ -d swift-nio-http-client.xcodeproj ]] || swift package generate-xcodeproj

# run jazzy
if ! command -v jazzy > /dev/null; then
  gem install jazzy --no-ri --no-rdoc
fi

module_switcher="docs/$version/README.md"
jazzy_args=(--clean
            --author 'SwiftNIOHTTPClient team'
            --readme "$module_switcher"
            --author_url https://github.com/swift-server/swift-nio-http-client
            --github_url https://github.com/swift-server/swift-nio-http-client
            --github-file-prefix "https://github.com/swift-server/swift-nio-http-client/tree/$version"
            --theme fullwidth
            --xcodebuild-arguments -scheme,swift-nio-http-client-Package)
cat > "$module_switcher" <<"EOF"
# SwiftNIOHTTPClient Docs

SwiftNIOHTTPClient is a Swift HTTTP Client package.

To get started with SwiftNIOHTTPClient, [`import NIOHTTPClient`](../NIOHTTPClient/index.html). The
most important type is [`HTTPClient`](https://swift-server.github.io/swift-nio-http-client/docs/current/NIOHTTPClient/Classes/HTTPClient.html)
which you can use to emit log messages.

EOF

tmp=`mktemp -d`
for module in "${modules[@]}"; do
  args=("${jazzy_args[@]}"  --output "$tmp/docs/$version/$module" --docset-path "$tmp/docset/$version/$module" --module "$module")
  if [[ -f "$root_path/.build/sourcekitten/$module.json" ]]; then
    args+=(--sourcekitten-sourcefile "$root_path/.build/sourcekitten/$module.json")
  fi
  jazzy "${args[@]}"
done

# push to github pages
if [[ $CI == true ]]; then
  BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
  GIT_AUTHOR=$(git --no-pager show -s --format='%an <%ae>' HEAD)
  git fetch origin +gh-pages:gh-pages
  git checkout gh-pages
  rm -rf "docs"
  cp -r "$tmp/docs" .
  cp -r "docs/$version" docs/current
  git add --all docs
  echo '<html><head><meta http-equiv="refresh" content="0; url=docs/current/NIOHTTPClient/index.html" /></head></html>' > index.html
  git add index.html
  touch .nojekyll
  git add .nojekyll
  changes=$(git diff-index --name-only HEAD)
  if [[ -n "$changes" ]]; then
    echo -e "changes detected\n$changes"
    git commit --author="$GIT_AUTHOR" -m "publish $version docs"
    git push origin gh-pages
  else
    echo "no changes detected"
  fi
  git checkout -f $BRANCH_NAME
fi
