#!/bin/bash
: <<=cut

Unpack MUT components.

=cut

set -e
set -u

DEB_SOURCE="$( dpkg-parsechangelog -SSource )"
DEB_VERSION_UPSTREAM="$( dpkg-parsechangelog -SVersion | sed -e 's/-[^-]*$//' )"

if ls ../${DEB_SOURCE}_${DEB_VERSION_UPSTREAM}.orig-*.tar.* 2>>/dev/null; then
    for T in ../${DEB_SOURCE}_${DEB_VERSION_UPSTREAM}.orig-*.tar.*; do
        C="${T##*.orig-}"
        C="${C%%.tar*}"
        [ -d "${C}" ] || mkdir -p "${C}"
        tar xf ${T} -C "${C}" --strip-components=2
    done
else
    printf "W: no components to extract.\n"
    exit 0
fi
