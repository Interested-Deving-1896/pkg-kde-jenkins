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
import re
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

    def add(self, parents, package, path=tuple()):
        if not parents:
            self.values[package.name] = package
            return
        head, tail = parents[:1], parents[1:]
        new_path = path + head
        subtree = self.subtrees.setdefault(head, Tree(new_path))
        subtree.add(tail, package, path=new_path)

    def compress(self):
        new_subs = {}
        for key, subtree in self.subtrees.items():
            new_sub = subtree.compress()
            new_subs[new_sub.path] = new_sub
        if len(new_subs) == 1 and not self.values:
            key, sub = new_subs.popitem()
            return sub
        else:
            self.subtrees = new_subs
        return self

    def __str__(self):
        return "{{Tree path: {}, subtrees: {}, values: {}}}".format(
            self.path, self.subtrees, self.values)

    def __iter__(self):
        yield self
        for key, value in self.subtrees.items():
            yield value


def group_packages(packages, basedir):
    ''' Group packages by directories hierarchies '''

    tree = Tree()
    groups = {}

    for package in packages:
        path = package.path
        if path.startswith(basedir):
            path = path[len(basedir):]
        dirs = tuple(path.lstrip(os.path.sep).split(os.path.sep))
        tree.add(dirs[:-1], package)
    tree = tree.compress()
    for parent in tree:
        print(parent.path)
        groups[parent.path[-1]] = parent

    return tree, groups


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
            return list(deb822.Deb822.iter_paragraphs(f))

    @property
    def tests_control(self):
        control_file = os.path.join(self.path, 'debian/tests/control')

        if not os.path.isfile(control_file):
            # No tests
            return []

        with open(control_file) as f:
            return list(deb822.Deb822.iter_paragraphs(f))

    @property
    def copyright(self):
        copyright_filename = os.path.join(self.path, 'debian/copyright')
        with open(copyright_filename) as f:
            return list(deb822.Deb822.iter_paragraphs(f))

    @property
    def build_depends(self):
        build_deps = []
        source_control = self.control[0]
        build_deps.append(source_control.get('Build-Depends'))
        build_deps.append(source_control.get('Build-Depends-Indep'))
        return ', '.join(x for x in build_deps if x)

    @property
    def runtime_depends(self):
        deps = []
        binary_controls = self.control[1:]
        for binary_control in binary_controls:
            deps.append(binary_control.get('Depends'))
        return ', '.join(x for x in deps if x)

    @property
    def recommends(self):
        deps = []
        binary_controls = self.control[1:]
        for binary_control in binary_controls:
            deps.append(binary_control.get('Recommends'))
        return ', '.join(x for x in deps if x)

    @property
    def tests_depends(self):
        tests_deps = []
        additionals = set()
        for test in self.tests_control:
            depends = test.get('Depends', '')
            depends_list = re.split(r'\s*,\s*', depends)
            if '@' in depends_list:
                depends_list.remove('@')
                additionals.add('runtime')
            if '@builddeps@' in depends_list:
                depends_list.remove('@builddeps@')
                additionals.add('build')
            restrictions = test.get('Restrictions', '')
            restrictions_list = re.split(r'\s*,\s*', restrictions)
            if 'needs-recommends' in restrictions_list:
                additionals.add('recommends')
            tests_deps.extend(depends_list)
        if 'runtime' in additionals:
            tests_deps.append(self.runtime_depends)
            if 'recommends' in additionals:
                tests_deps.append(self.recommends)
        if 'build' in additionals:
            tests_deps.append(self.build_depends)

        return ', '.join(x for x in tests_deps if x)

    @property
    def list_packages(self):
        'A simple dh_listpackages'
        packages = []
        for part in self.control:
            package_name = part.get('Package')
            if package_name:
                packages.append(package_name)
        return packages

    @property
    def description(self):
        for block in self.control:
            if 'Description' in block:
                return block['Description']
        return ''

    @property
    def short_description(self):
        return self.description.split('\n', 2)[0]

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
        return self.control[0].get('Source')

    @property
    def vcs(self):
        ''' Vcs uri '''
        control = self.control[0]
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
        upstream_metadata = self.upstream_metadata
        if upstream_metadata:
            name = upstream_metadata.get('Name')
            if name:
                return name
        copyright = self.copyright[0]
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

        upstream_metadata = self.upstream_metadata
        if upstream_metadata:
            vcs = self.upstream_metadata.get('Repository')
            if vcs:
                return vcs
        copyright = self.copyright[0]
        if copyright and copyright.get('Source'):
            return copyright.get('Source')
        control = self.control[0]
        return control.get('Homepage')

    def __repr__(self):
        return '(Package path:{} )'.format(self.path)

    def __str__(self):
        return self.path


def obtain_packages(dirs, basedir):
    packages = (Package(os.path.join(basedir, d)) for d in dirs)
    return list(packages)


def print_descriptions(packages):
    for package in packages:
        print(package.short_description)


def package_relations(binaries, dependencies):
    '''Process dependencies against binaries

    :binaries: is a dictionary that maps binaries to the package_name
               that generates it.
    :dependencies: is a dpkg depends string
    :returns: a mapping, of the package_names that generate the needed
              binaries, and the binaries that cause the dependency as the
              value.
    '''
    bin_deps = set()
    rels = deb822.PkgRelation.parse_relations(dependencies)
    for or_part in rels:
        for part in or_part:
            bin_deps.add(part['name'])
    internal_dep = {}
    for dep in bin_deps:
        if dep in binaries:
            internal_dep.setdefault(binaries[dep], []).append(dep)
    return internal_dep


def process_dependencies(packages):
    binaries = {}
    for package in packages:
        name = package.name
        for binary in package.list_packages:
            if binary in binaries:
                print('ERROR: The package {} seems to be produced by two '
                      'or more source packages: {}, {}'.format(
                          binary,
                          binaries[binary],
                          name))
            else:
                binaries[binary] = name
    relations = {}
    for package in packages:
        build_depends = package.build_depends
        relations.setdefault(package.name, {})['build'] = \
            package_relations(binaries, build_depends)
        test_dependencies = package.tests_depends
        relations[package.name]['test'] = \
            package_relations(binaries, test_dependencies)
    return relations


def prepare_projects(group_tree, dependencies, local_repository, local_vcs):
    projects = []
    for group in group_tree:
        print(group)
        if not group.values:
            continue
        project = {}
        projects.append({'project': project})
        project['name'] = '-'.join(group.path[-1:])
        project['jobs'] = ['{}-{{item}}'.format(project['name'])]
        if local_repository:
            project['local_repository'] = local_repository
        items = []
        project['item'] = items
        for name, package in group.values.items():
            item = {}
            items.append({name: item})
            item['description'] = package.short_description
            item['build_dependencies'] = list(
                '{}_build'.format(d) for d in dependencies[name]['build'])
            item['test_dependencies'] = list(
                '{}_build'.format(d) for d in dependencies[name]['test'])
            if local_vcs:
                item['local_vcs'] = "{}/{}/{}.git".format(
                    local_vcs, os.path.join(*group.path), name)
            item['debian_vcs'] = package.vcs.uri
            item['upstream_vcs'] = package.upstream_vcs
    return projects


def dump_projects(projects, output):
    yaml.dump(projects, output)


def main():
    argparser = argparse.ArgumentParser(description=__doc__,
                                        fromfile_prefix_chars='@')
    argparser.add_argument('package_directory', help='Debian package directories',
                           nargs='+')
    argparser.add_argument('-o', '--output', type=argparse.FileType('w'),
                           help='Output file', default=sys.stdout)
    argparser.add_argument('--basedir', default='~')
    # TODO: first try to give the local repository, unsuccessful
    # it needs a {distribution} in the middle, :(
    argparser.add_argument('--local-repository', default='')
    argparser.add_argument('--local-vcs', default='')
    args = argparser.parse_args()

    packages = obtain_packages(args.package_directory, args.basedir)
    packages_relations = process_dependencies(packages)
    group_tree, groups = group_packages(packages, args.basedir)
    projects = prepare_projects(group_tree, packages_relations,
                                args.local_repository,
                                args.local_vcs)
    dump_projects(projects, args.output)


if __name__ == "__main__":
    main()
