#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
Generate jenkings-job-builder yaml file from a set of Debian package
repositories.

Optionally it will generate projects from the directories hierachy.
'''

import argparse
import os
import sys

import debian.deb822 as deb822
import yaml


class Package(object):

    ''' Information about the package '''

    def __init__(self, path):
        ''' path: Package directory '''

        assert(os.path.isdir(path))
        self.path = path

    @property
    def control(self):
        control_file = os.path.join(self.path, 'debian/control')

        with open(control_file) as f:
            return deb822.Deb822.iter_paragraphs(f)

    @property
    def copyright(self):
        copyright_filename = os.path.join(self.path, 'debian/copyright')
        with open(copyright_filename) as f:
            return deb822.Deb822.iter_paragraphs(f)

    @property
    def upstream_metadata(self):
        ''' Obtain the contents of the debian/upstream/metadata file '''
        metadata_filename = os.path.join(self.path, 'debian/upstream/metadata')
        if not os.path.exists(metadata_filename):
            return
        with open(metadata_filename) as f:
            return yaml.load(f)

    @property
    def source_name(self):
        ''' Source package name '''
        control = next(self.control)
        return control.get('Source')

    @property
    def vcs(self):
        ''' Vcs uri '''
        control = next(self.control)
        for vcs_key in ['Git', 'Svn', 'Arch', 'Bzr', 'Cvs', 'Darcs', 'Hg', 'Mtn']:
            key = 'Vcs-{}'.format(vcs_key)
            if key in control:
                vcs = control[key]
                if vcs_key == 'Git':
                    # Handle -b for branch
                    parts = vcs.rsplit('-b', 2)
                    if len(parts) == 2:
                        self.branch = parts[1].strip()
                    vcs = parts[0].strip()
                return vcs

    @property
    def upstream_name(self):
        ''' Obtain upstream_name.

    Use the information from the debian/upstream/metadata file(DEP12),
    if that's not available, use the Upstream-Name field in the debian/copyright
    (if it's in DEP5 format), and fallback to use the Source field
    from the control file.
        '''

        name = self.upstream_metadata.get('Name')
        if name:
            return name
        copyright = next(self.copyright)
        if copyright and copyright.get('Upstream-Name'):
            return copyright.get('Upstream-Name')
        return self.source_name

    @property
    def upstream_vcs(self):
        ''' Obtain upstream_vcs.

    Use the information from the debian/upstream/metadata file(DEP12),
    if that's not available, use the Source field in the debian/copyright
    (if it's in DEP5 format), and fallback to use the Homepage field
    from the control file.
        '''

        vcs = self.upstream_name.get('Repository')
        if vcs:
            return vcs
        copyright = next(self.copyright)
        if copyright and copyright.get('Source'):
            return copyright.get('Source')
        control = next(self.control)
        return control.get('Homepage')

    def __str__(self):
        return self.path


def obtain_packages(dirs):
    full_dirs = (os.path.abspath(d) for d in dirs)
    return list(full_dirs)


def dump_packages(packages, output):
    yaml.dump(packages, output)


def main():
    argparser = argparse.ArgumentParser(description=__doc__,
                                        fromfile_prefix_chars='@')
    argparser.add_argument('package_directory', help='Debian package directories',
                           nargs='+')
    argparser.add_argument('-o', '--output', type=argparse.FileType('w'),
                           help='Output file', default=sys.stdout)
    args = argparser.parse_args()

    packages = obtain_packages(args.package_directory)
    dump_packages(packages, args.output)


if __name__ == "__main__":
    main()
