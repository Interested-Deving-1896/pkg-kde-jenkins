#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import configparser
import heapq
import logging
import subprocess
import sys

import debian.debian_support as debian_support
import jenkins


Version = debian_support.Version


def process_options():

    kw = {
        'format': '[%(levelname)s] %(message)s',
    }

    arg_parser = argparse.ArgumentParser(
        description='List jenkins jobs unders certain criterias',
        fromfile_prefix_chars='@')
    arg_parser.add_argument('-c', '--config', default='jenkins.ini')
    arg_parser.add_argument('--debug', action='store_true')
    arg_parser.add_argument('-D', '--distribution', default='unstable')
    arg_parser.add_argument('--mode', default='todo',
                            choices=['todo', 'fix', 'unreleased', 'topsort',
                                     'trigger'])
    arg_parser.add_argument('--trigger', action='store_true')
    arg_parser.add_argument('--packages', nargs='+')
    args = arg_parser.parse_args()

    if args.debug:
        kw['level'] = logging.DEBUG

    logging.basicConfig(**kw)

    return args


def connect(options):
    config = configparser.ConfigParser()
    config.read(options.config)
    jenkins_url = config.get("jenkins", "url")
    jenkins_user = config.get("jenkins", "user")
    jenkins_pass = config.get("jenkins", "password")

    server = jenkins.Jenkins(jenkins_url, jenkins_user, jenkins_pass)
    return server


def test(server):
    version = server.get_version()

    print(version)

    jobs = server.get_jobs()

    print('###\n# jobs\n###')
    for job in jobs:
        print('Name: {}'.format(job['fullname']))
        for key, value in job.items():
            print('{}: {}'.format(key, value))
        print()

    # fullname = jobs[0]['fullname']
    # fullname = 'extra-cmake-modules_prepare'
    fullname = 'kwin_build'
    job_info = server.get_job_info(fullname)

    print('###\n# info for {} \n###'.format(fullname))
    for key, value in job_info.items():
        print('{}: {}'.format(key, value))

    for build in job_info['builds']:
        build_info = server.get_build_info(fullname, build['number'])
        print('###\n# info for build\n###')
        for key, value in build_info.items():
            print('{}: {}'.format(key, value))


def get_dsc_name(build_info):
    for artifact in build_info.get('artifacts', []):
        if artifact['fileName'].endswith('.dsc'):
            return artifact['fileName']


def get_parameters(build_info):
    actions = build_info['actions']
    for action in actions:
        if 'parameters' not in action:
            continue
        parameters = action['parameters']
        break
    else:
        parameters = [{'name': 'DISTRIBUTION', 'value': 'unreleased'}]
    return parameters


def get_distribution_value(parameters):
    for parameter in parameters:
        if parameter['name'] != 'DISTRIBUTION':
            continue
        value = parameter['value']
        break
    else:
        value = 'unreleased'
    return value


def get_build_infos(server, job_info, distributions):
    infos = {}
    for build in job_info['builds']:
        build_info = server.get_build_info(job_info['name'], build['number'])
        parameters = get_parameters(build_info)
        value = get_distribution_value(parameters)
        # Probably "building"
        if 'result' not in build_info or build_info['result'] is None:
            continue

        if value in distributions and value not in infos:
            infos[value] = build_info
        if len(distributions) == len(infos):
            break
    return infos


def latest_build(server, job, distribution):
    name = job['fullname']
    package, part = name.split('_', 1)
    job_info = server.get_job_info(name)
    result = {}

    distributions = {'unreleased', distribution}
    if distribution == 'experimental':
        distributions.add('unstable')
    latest_infos = get_build_infos(server, job_info, distributions)
    for distribution, info in latest_infos.items():
        result[distribution] = {}
        result[distribution]['status'] = info.get('result', 'FAILURE')
        dsc_name = get_dsc_name(info)
        if dsc_name:
            source_name, version = dsc_name.split('_', 1)
            version = version.replace('.dsc', '')
            result[distribution]['source_name'] = source_name
            result[distribution]['version'] = version
    deps = set(x['name'].split('_', 1)[0]
               for x in job_info.get('upstreamProjects', []))
    if package in deps:
        deps.remove(package)
    return package, part, result, deps


def status(package):
    def _status(part):
        return package.get(part, {}).get('status', 'FAILURE') == 'SUCCESS'
    return _status('prepare') and _status('build') and _status('test')


def tests_unstable(package):

    def _status(part):
        return package.get(part, {}).get('status', 'FAILURE') == 'SUCCESS'

    def _unstable(part):
        return package.get(part, {}).get('status', 'FAILURE') == 'UNSTABLE'
    return _status('prepare') and _status('build') and _unstable('test')


def latest_package(package, packages, distributions):
    max_version = Version('0')
    at_distribution = {}
    for d in distributions:
        p = packages.get(package, {}).get(d, {})
        version = Version(p.get('version', '0'))
        if version > max_version:
            at_distribution = p
            max_version = version
    return at_distribution


def check_deps(package, packages, distributions):
    for dep in package.get('deps', set()):
        at_distribution = latest_package(dep, packages, distributions)
        if not (status(at_distribution) or tests_unstable(at_distribution)):
            return False
    return True


def check_deps_version(package, packages, distributions):
    for dep in package.get('deps', set()):
        dep_package = packages.get(dep, {})
        at_distribution = latest_package(dep, packages, distributions)
        if 'version' not in at_distribution:
            if 'debian_version' not in dep_package:
                return False
            at_unreleased = packages[dep].get('unreleased', {}).get('version', '0')
            if dep_package['debian_version'] >= Version(at_unreleased):
                continue
            return False

        new_version = debian_support.Version(at_distribution['version'])
        if 'debian_version' not in dep_package:
            return False
        if new_version.upstream_version > dep_package['debian_version'].upstream_version:
            return False
    return True


def get_packages(server, distribution):
    packages = {}
    jobs = server.get_jobs()
    for job in jobs:
        package, part, result, deps = latest_build(server, job, distribution)
        if package not in packages:
            d = {}
            packages[package] = d
        d.setdefault('deps', set()).update(deps)
        for dist, value in result.items():
            if dist not in d:
                d[dist] = {}
            d[dist][part] = value
            if 'source_name' in value and 'source_name' not in d:
                d['source_name'] = value['source_name']
            if part == 'prepare' and 'version' in value and 'version' not in d[dist]:
                d[dist]['version'] = value['version']
    return packages


def version_at_distribution(source_name, distributions):
    # cmd = ['rmadison', '-u', 'udd', source_name]
    cmd = ['rmadison', source_name]
    output = subprocess.check_output(cmd, universal_newlines=True)
    version = '0'
    for line in output.split('\n'):
        if '|' not in line:
            continue
        fields = line.split('|')
        if 'source' not in fields[3]:
            continue
        d = fields[2].strip()
        if 'new' == d:
            continue
        if 'experimental' not in distributions and \
           'experimental' in d:
            continue
        new_version = Version(fields[1].strip())
        if not version:
            version = new_version
        elif version < new_version:
            version = new_version
    return version


def get_ready(packages, distributions):
    ready = {}
    # process packages and collect the packages for the second_phase
    second_phase = set()
    for package_name, package in packages.items():
        # print(package_name, package)
        if not (status(package.get('unreleased', {})) or
                tests_unstable(package.get('unreleased', {}))):
            continue
        # print(package_name)
        if not check_deps(package, packages, distributions):
            continue

        version = version_at_distribution(package['source_name'],
                                          distributions)
        epochless = Version(version)
        epochless.epoch = None
        # print(version, epochless)
        package['debian_version'] = epochless

        second_phase.add(package_name)

    for package_name in second_phase:
        package = packages[package_name]

        new_version = debian_support.Version(package['unreleased']['version'])
        if new_version <= package['debian_version']:
            continue

        if not check_deps_version(package, packages, distributions):
            continue

        p = latest_package(package_name, packages, distributions)
        status_ok = status(p)
        status_unstable = tests_unstable(p)
        newer = (status_ok or status_unstable) and (debian_support.Version(
            p['version']) > epochless)

        if status_ok and newer:
            ready.setdefault('upload', set()).add(package_name)
            print('{} {}={} UPLOAD, currently: {}'.format(
                package_name, package['source_name'], new_version,
                version))
        elif status_unstable and newer:
            ready.setdefault('unstable', set()).add(package_name)
            print('{} {}={} UNSTABLE, currently: {}'.format(
                package_name, package['source_name'], new_version,
                version))
        else:
            ready.setdefault('build', set()).add(package_name)
            print('{} {}={} BUILD, currently: {}'.format(
                package_name, package['source_name'], new_version,
                version))

    return ready


def topsort_tiers(packages, ready):
    ready['all'] = ready.get('upload', set()) | \
        ready.get('unstable', set()) | \
        ready.get('build', set())
    heap = []
    # Prepare rdeps to complete the graph
    for name in ready['all']:
        package = packages[name]
        ready_deps = package.get('deps', set()) & ready['all']
        ready_deps -= {name}
        for dep in ready_deps:
            packages[dep].setdefault('rdeps', set()).add(name)
        packages[name]['ready_deps'] = ready_deps
        packages[name]['deps_required'] = len(ready_deps)
        packages[name]['tier'] = 0
        if packages[name]['deps_required'] == 0:
            heapq.heappush(heap, (packages[name]['tier'], name))
    tiers = []
    sanity_check = 0
    while heap:
        tier, name = heapq.heappop(heap)
        sanity_check += 1
        package = packages[name]
        if tier >= len(tiers):
            tiers.append(set())
        tiers[tier].add(name)
        for rdep_name in package.get('rdeps', set()):
            rdep = packages[rdep_name]
            rdep['ready_deps'].remove(name)
            rdep['deps_required'] -= 1
            rdep['tier'] = package['tier'] + 1
            if rdep['deps_required'] == 0:
                heapq.heappush(heap, (rdep['tier'], rdep_name))
    if len(ready['all']) != sanity_check:
        print('ERROR: We processed {} of {}, something is '
              'wrong'.format(sanity_check, len(ready['all'])))
        for name in ready['all']:
            package = packages[name]
            if package['ready_deps']:
                print('name: {} missing {}'.format(
                    name, package['ready_deps']))
    return tiers


def list_todo_distribution(server, packages, trigger, distribution):
    # Obtain jobs
    # for each job, obtain the builds
    # check if the build parameter DISTRIBUTION matches the distribution, and
    # keep the information of the newest matching job.
    distributions = {distribution}
    if distribution == 'experimental':
        distributions.add('unstable')
    ready = get_ready(packages, distributions)
    tiers = topsort_tiers(packages, ready)

    for tier, items in enumerate(tiers):
        print('\n###\n# Tier {}\n###'.format(tier + 1))
        print('\n###\n# Upload\n###')
        if 'upload' in ready:
            for package in ready['upload'] & items:
                print(package)
        print('\n###\n# UNSTABLE\n###')
        if 'unstable' in ready:
            for package in ready['unstable'] & items:
                print(package)
        print('\n###\n# BUILD\n###')
        if 'build' in ready:
            for package in ready['build'] & items:
                print(package)
        if tier == 0 and trigger and 'build' in ready:
            for package in ready['build'] & items:
                job_name = '{}_prepare'.format(package)
                server.build_job(job_name, {'DISTRIBUTION': distribution})


def list_fix(packages):

    for package_name, package in packages.items():
        try:
            prepare_version = debian_support.Version(
                package['unreleased']['prepare']['version'])
        except Exception:
            print('{}: no version in prepare, {}'.format(package_name, package))
            prepare_version = debian_support.Version('0')
        try:
            test_version = debian_support.Version(
                package['unreleased']['test']['version'])
        except Exception:
            print('{}: no version in test, {}'.format(package_name, package))
            test_version = debian_support.Version('0')
        if prepare_version > test_version:
            print('{} prepare={} test={}'.format(
                package_name, prepare_version, test_version))


def list_unreleased(packages):

    def _status(package, part):
        return package.get(part, {}).get('status', 'MISSING')

    for package_name, package in packages.items():
        p = package.get('unreleased', {})
        if status(p):
            continue
        print('{}: prepare:{} build:{} test:{}'.format(
            package_name, _status(p, 'prepare'), _status(p, 'build'),
            _status(p, 'test')))


def list_topsort(server, packages, trigger, distribution):

    distributions = {distribution}
    if distribution == 'experimental':
        distributions.add('unstable')

    heap = []
    for name, package in packages.items():
        deps = package.get('deps', set()) - {name}
        deps &= packages.keys()
        for dep in deps:
            packages[dep].setdefault('rdeps', set()).add(name)
        packages[name]['deps_required'] = deps
        packages[name]['tier'] = 0
        if len(deps) == 0:
            heapq.heappush(heap, (0, name))
    tiers = []
    sanity_check = 0
    while heap:
        tier, name = heapq.heappop(heap)
        package = packages[name]
        sanity_check += 1
        for i in range(len(tiers) - 1, tier + 1):
            tiers.append(set())
        tiers[tier].add(name)
        for rdep_name in package.get('rdeps', set()):
            rdep = packages[rdep_name]
            rdep['deps_required'].remove(name)
            rdep['tier'] = package['tier'] + 1
            if len(rdep['deps_required']) == 0:
                heapq.heappush(heap, (rdep['tier'], rdep_name))
    if len(packages) != sanity_check:
        print('ERROR: We processed {} of {}, something is '
              'wrong'.format(sanity_check, len(packages)))
        for name, package in packages.items():
            if package['deps_required']:
                print('name: {} missing {}'.format(
                    name, package['deps_required']))

    second_phase = set()
    for name, package in packages.items():
        package['status'] = ''
        if not (status(package.get('unreleased', {})) or
                tests_unstable(package.get('unreleased', {}))):
            package['status'] = 'unreleased build'
            continue
        if not check_deps(package, packages, {'unreleased'}):
            package['status'] = 'unreleased deps'
            continue
        version = version_at_distribution(package['source_name'], distributions)
        epochless = debian_support.Version(version)
        epochless.epoch = None
        package['debian_version'] = epochless
        new_version = debian_support.Version(package['unreleased']['version'])
        if new_version < package['debian_version']:
            package['status'] = 'unreleased old'
            continue
        elif new_version == package['debian_version']:
            package['status'] = 'uploaded'
            continue
        second_phase.add(name)
    for name in second_phase:
        package = packages[name]
        if not check_deps_version(package, packages, distributions):
            package['status'] = 'missing dependency'
            continue
        p = latest_package(name, packages, distributions)
        status_ok = status(p)
        status_unstable = tests_unstable(p)
        newer = (status_ok or status_unstable) and (debian_support.Version(
            p['version']) > package['debian_version'])
        if status_ok and newer:
            package['status'] = 'upload'
        elif status_unstable and newer:
            package['status'] = 'unstable'
        else:
            package['status'] = 'build'
            if trigger:
                job_name = '{}_prepare'.format(name)
                server.build_job(job_name, {'DISTRIBUTION': distribution})

    for tier, items in enumerate(tiers):
        print('\n###\n# Tier {}\n###'.format(tier + 1))
        xs = sorted(items)
        for name in xs:
            package = packages[name]
            versions = {}
            if 'debian_version' in package:
                versions['debian'] = package['debian_version']
            for d in distributions | {'unreleased'}:
                if d not in package:
                    continue
                if 'version' in package[d]:
                    versions[d] = package[d]['version']

            print('{name}: {status} {versions}'.format(name=name,
                                                       status=package['status'],
                                                       versions=versions))


def trigger(server, options):
    for package in options.packages:
        job_name = '{}_prepare'.format(package)
        server.build_job(job_name, {'DISTRIBUTION': options.distribution})


def main():
    options = process_options()
    server = connect(options)

    if options.mode == 'unreleased':
        options.distribution = 'unreleased'
    elif options.mode == 'trigger':
        trigger(server, options)
        sys.exit(0)

    packages = get_packages(server, options.distribution)

    if options.mode == 'todo':
        list_todo_distribution(server, packages, options.trigger,
                               options.distribution)
    elif options.mode == 'fix':
        list_fix(packages)
    elif options.mode == 'unreleased':
        list_unreleased(packages)
    elif options.mode == 'topsort':
        list_topsort(server, packages, options.trigger, options.distribution)

    # test(server)
    sys.exit(0)


if __name__ == "__main__":
    main()
