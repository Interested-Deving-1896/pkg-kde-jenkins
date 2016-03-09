#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
Generate jenkings-job-builder yaml file from a set of Debian package
repositories.

Optionally it will generate projects from the directories hierachy.
'''

import argparse
import collections
import os
import sys

import debian.deb822 as deb822
import yaml


DebianVcs = collections.namedtuple('DebianVcs', ['type', 'uri', 'branch'])


class Tree(object):

    ''' Group packages by directories hierachies '''

    def __init__(self, path=None):
        if not path:
            path = ()
        self.path = path
        self.subtrees = {}
        self.values = {}

    def add(self, parents, package):
        if not parents:
            self.values[package.name] = package
            return
        head, tail = parents[:1], parents[1:]
        subtree = self.subtrees.setdefault(head, Tree(head))
        subtree.add(tail, package)

    def compress(self):
        new_subs = {}
        for key, subtree in self.subtrees.items():
            new_sub = subtree.compress()
            new_subs[new_sub.path] = new_sub
        if len(new_subs) == 1 and not self.values:
            key, sub = new_subs.popitem()
            sub.path = self.path + sub.path
            return sub
        else:
            self.subtrees = new_subs
        return self

    def __str__(self):
        return "{{Tree path: {}, subtrees: {}, values: {}}}".format(
            self.path, self.subtrees, self.values)


def group_packages(packages):
    ''' Group packages by directories hierarchies '''

    tree = Tree()

    for package in packages:
        dirs = tuple(package.path.lstrip(os.path.sep).split(os.path.sep))
        tree.add(dirs[:-1], package)
        print(tree)
    tree = tree.compress()
    print(tree)

    return tree

class Package(object):

    ''' Information about the package '''

    def __init__(self, path):
        ''' path: Package directory '''

        assert(os.path.isdir(path))
        self.path = path

    @property
    def name(self):
        return os.path.split(self.path)[-1]

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
        for vcs_type in ['Git', 'Svn', 'Arch', 'Bzr', 'Cvs', 'Darcs', 'Hg', 'Mtn']:
            key = 'Vcs-{}'.format(vcs_type)
            if key in control:
                uri = control[key]
                branch = None
                if vcs_type == 'Git':
                    # Handle -b for branch
                    parts = uri.rsplit('-b', 2)
                    if len(parts) == 2:
                        branch = parts[1].strip()
                    uri = parts[0].strip()
                return DebianVcs(vcs_type, uri, branch)

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

    def __repr__(self):
        return '(Package path:{} )'.format(self.path)

    def __str__(self):
        return self.path


def obtain_packages(dirs):
    full_dirs = (os.path.abspath(d) for d in dirs)
    packages = (Package(d) for d in full_dirs)
    return list(packages)


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
    print(packages)
    group_tree = group_packages(packages)
    dump_packages(packages, args.output)


if __name__ == "__main__":
    main()
