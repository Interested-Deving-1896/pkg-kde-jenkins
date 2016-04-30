#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import configparser
import logging
import subprocess
import sys

import debian.debian_support as debian_support
import jenkins


def process_options():

    kw = {
        'format': '[%(levelname)s] %(message)s',
    }

    arg_parser = argparse.ArgumentParser(
        description='List jenkins jobs unders certain criterias')
    arg_parser.add_argument('-c', '--config', default='jenkins.ini')
    arg_parser.add_argument('--debug', action='store_true')
    arg_parser.add_argument('--distribution', default='unreleased')
    arg_parser.add_argument('--mode', default='todo', choices=['todo', 'fix'])
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

        if value in distributions and value not in infos:
            infos[value] = build_info
        if len(distributions) == infos:
            break
    return infos


def latest_build(server, job):
    name = job['fullname']
    package, part = name.split('_', 1)
    job_info = server.get_job_info(name)
    result = {}

    latest_infos = get_build_infos(server, job_info,
                                   set(('unreleased', 'unstable')))
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


def check_deps(package, packages):
    for dep in package.get('deps', set()):
        unstable = packages.get(dep, {}).get('unstable', {})
        if not status(unstable):
            return False
    return True


def get_packages(server):
    packages = {}
    jobs = server.get_jobs()
    for job in jobs:
        package, part, result, deps = latest_build(server, job)
        if package not in packages:
            d = {}
            packages[package] = d
        d.setdefault('deps', set()).update(deps)
        for distribution, value in result.items():
            if distribution not in d:
                d[distribution] = {}
            d[distribution][part] = value
            if 'source_name' in value and 'source_name' not in d:
                d['source_name'] = value['source_name']
            if 'version' in value and 'version' not in d[distribution]:
                d[distribution]['version'] = value['version']
    return packages


def version_at_distribution(source_name):
    # ftpmasters dak interface responds very sparsely
    cmd = ['rmadison', '--url=udd', source_name]
    output = subprocess.check_output(cmd, universal_newlines=True)
    version = None
    for line in output.split('\n'):
        if '|' not in line:
            continue
        fields = line.split('|')
        new_version = debian_support.Version(fields[1].strip())
        if not version:
            version = new_version
        elif version < new_version:
            version = new_version
    return version


def list_todo_distribution(packages):
    # Obtain jobs
    # for each job, obtain the builds
    # check if the build parameter DISTRIBUTION matches the distribution, and
    # keep the information of the newest matching job.

    ready = {}
    for package_name, package in packages.items():
        # print(package_name, package)
        if not status(package['unreleased']):
            continue
        # print(package_name)
        if not check_deps(package, packages):
            continue

        version = version_at_distribution(package['source_name'])
        epochless = debian_support.Version(version)
        epochless.epoch = None
        # print(version, epochless)

        if not status(package.get('unstable', {})):
            new_version = debian_support.Version(
                package['unreleased']['version'])
            if new_version > epochless:
                ready.setdefault('build', set()).add(package_name)
                print('{} {}={} BUILD, currently: {}'.format(
                    package_name, package['source_name'], new_version,
                    version))
        else:
            new_version = debian_support.Version(
                package['unstable']['version'])
            if new_version > epochless:
                ready.setdefault('upload', set()).add(package_name)
                print('{} {}={} UPLOAD, currently: {}'.format(
                    package_name, package['source_name'], new_version,
                    version))

    print('\n###\n# Upload\n###')
    for package in ready['upload']:
        print(package)
    print('\n###\n# BUILD\n###')
    for package in ready['build']:
        print(package)


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


def main():
    options = process_options()
    server = connect(options)

    packages = get_packages(server)

    if options.mode == 'todo':
        list_todo_distribution(packages)
    elif options.mode == 'fix':
        list_fix(packages)

    # test(server)
    sys.exit(0)


if __name__ == "__main__":
    main()
