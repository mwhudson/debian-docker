#!/bin/bash
: <<=cut

=head1 DESCRIPTION

This script is called by uscan(1) as per "debian/watch" to download Multi
Upstream Tarball (MUT) components.

=head1 COPYRIGHT

Copyright: 2018 Dmitry Smirnov <onlyjob@member.fsf.org>

=head1 LICENSE

License: GPL-3+
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 .
 This package is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 .
 You should have received a copy of the GNU General Public License
 along with this program. If not, see <http://www.gnu.org/licenses/>.

=cut

set -e
set -u

if [ "$1" = '--upstream-version' ]; then
    version="$2"
else
    printf "E: missing argument '--upstream-version'.\n" 1>&2
    exit 1
fi

export XZ_OPT="-6v"
DEB_SOURCE="$( dpkg-parsechangelog -SSource )"
#DEB_VERSION="$( dpkg-parsechangelog -SVersion )"
filename="$( readlink -f ../${DEB_SOURCE}_${version}.orig.tar.xz )"
[ -s "${filename}" ] || exit 1

get_vendor_tree() {
    # Get the list of vendor directories. For github.com repositories, we want to descend
    # 2 levels down the directory, so that we get a list of go packages.
    local top_dirs=""
    local github_dirs=""

    for dir in "$@"; do
        if [ -d $dir ]; then
            top_dirs="$top_dirs $dir"
        fi
        if [ -d $dir/github.com ]; then
            github_dirs="$github_dirs $dir/github.com"
        fi
    done

    local top_vendored_dirs=$( find $top_dirs -mindepth 1 -maxdepth 1 -type d | grep -v 'github.com' )
    local github_vendored_dirs=$( find $github_dirs -mindepth 2 -maxdepth 2 -type d )
    printf "${top_vendored_dirs}\n${github_vendored_dirs}" \
        | sed 's;^.*/vendor/;vendor/;' \
        | sort
}

drop_files_excluded() {
    local work_dir
    for work_dir in $@; do
        perl -0nE 'say $1 if m{^Files\-Excluded:\s*(.*?)(?:\n\n|^Files|^Comment)}sm;' debian/copyright \
        | ( cd "${work_dir}" && xargs --no-run-if-empty rm -rf )
    done
    if [ -d "${work_dir}"/vendor ]; then
        find "${work_dir}"/vendor -mindepth 1 -type d -empty -delete -printf 'removed %p\n'
    fi
}

## extract main tarball:
work_dir="$( mktemp -d -t get-orig-source_${DEB_SOURCE}_XXXXXXXX )"
trap "rm -rf '${work_dir}'" EXIT
tar -xf "${filename}" -C "${work_dir}"

## Docker specific:
vendored_dirs="$(get_vendor_tree ${work_dir}/*/components/*/vendor)"
drop_files_excluded "${work_dir}"/*/components/*

#### Move components one level up
( cd "${work_dir}"/*/components && mv * ../ ) \
&& rmdir "${work_dir}"/*/components

( cd "${work_dir}" && tar -caf "${filename}" . )

## fetch Docker components:
for I in docker/go-events docker/go-metrics docker/libnetwork docker/distribution docker/swarmkit containerd/containerd; do
    printf ":: Processing ${I}\n" 1>&2
    URL="github.com/${I}"
    REV=$( grep "${URL}" "${work_dir}"/*/engine/vendor.conf | head -1 | awk '{print $2}' )
    if [ -z "${REV}" ]; then
        printf "E: could not find commit for ${I}\n" 1>&2
        exit 1
    fi
    component=${I##*/}
    FN="$( readlink -f ../${DEB_SOURCE}_${version}.orig-${component}.tar.gz )"

    if [ ! -s "${FN}" ]; then
        wget --tries=3 --timeout=40 --read-timeout=40 --continue \
          -O "${FN}" "https://${URL}/archive/${REV}.tar.gz" \
        || rm -f "${FN}"

        component_dir="$( mktemp -d -t get-orig-source_XXXXXXXX )"
        mkdir "${component_dir}"/${component}
        tar -xf "${FN}" -C "${component_dir}"/${component} --strip-components=1

        if [ -d "${component_dir}"/${component}/vendor ]; then
            vendored_dirs="$(printf '%s\n' ${vendored_dirs} $(get_vendor_tree ${component_dir}/${component}/vendor))"
        fi
        drop_files_excluded "${component_dir}"/${component}

        ( cd "${component_dir}" && tar -caf "${FN}" . )
        rm -rf "${component_dir}"

        mk-origtargz --package ${DEB_SOURCE} --version ${version} \
          --rename --repack --compression xz --directory .. \
          --component ${component} --copyright-file debian/copyright \
        "${FN}"
    fi
done
#####

echo ""
echo "Here's a tentative list for your Files-Excluded list, in d/copyright."
echo "Use it with care"
echo ""

echo "Files-Excluded:"
echo "${vendored_dirs}" | sort | uniq | sed 's/^/    /'

rm -rf "${work_dir}"
