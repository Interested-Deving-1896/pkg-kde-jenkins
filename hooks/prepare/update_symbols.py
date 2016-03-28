#!/usr/bin/env python3

import argparse
import glob
import logging
import os
import sys


def process_options():

    kw = {
        'format': '[%(levelname)s] %(message)s',
    }

    arg_parser = argparse.ArgumentParser(
        description='Update symbols files with the logs from the buildds.')
    arg_parser.add_argument('-d', '--package-dir', default='repo')
    arg_parser.add_argument('--debug', default=False)
    args = arg_parser.parse_args()

    if args.debug:
        kw['level'] = logging.DEBUG

    logging.basicConfig(**kw)

    return args


def symbols_files(basedir):
    return glob.glob(os.path.join(basedir, 'debian/*.symbols'))


def main():
    options = process_options()

    if not symbols_files(options.package_dir):
        logging.info('No symbols files, ignoring.')
        sys.exit(0)

    print(os.environ)

    if not options.no_act:
        pass


if __name__ == '__main__':
    main()
