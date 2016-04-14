#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import re
import sys

from junit_xml import TestSuite, TestCase


def update_description(tag, description):
    if tag and description:
        tag['description'] = description
    return ''


def read_lintian_output(input_file):
    tags = []

    comment_re = r'N:\s(?P<comment>[^\s].*)'
    description_re = r'N:\s{4}(?P<description>.*)'
    tag_re = (r'(?P<level>[A-Z]):\s(?P<package>[^:]*):\s'
              r'(?P<note>(?P<tag>[^\s]*)(\s(?P<extra>.*))?)')
    comment = ''
    description = ''
    last_tag = None
    for line in input_file:
        line = line.rstrip('\n')
        m = re.match(comment_re, line)
        if m:
            comment += m.group('comment')
            continue
        m = re.match(description_re, line)
        if m:
            description += m.group('description') + '\n'
            continue
        m = re.match(tag_re, line)
        if not m:
            continue
        description = update_description(last_tag, description)
        tag = {}
        tags.append(tag)
        last_tag = tag
        if comment:
            tag['comment'] = comment
            comment = ''
        tag['level'] = m.group('level')
        tag['package'] = m.group('package')
        tag['note'] = m.group('note')
        tag['tag'] = m.group('tag')
        tag['output'] = line
        extra = m.group('extra')
        if extra:
            tag['extra'] = extra
    description = update_description(last_tag, description)

    return tags


def generate_test_cases(tags):
    test_cases = []
    for tag in tags:
        test_case = TestCase(tag['note'], tag['package'])
        test_case.stdout = tag.get('comment')
        if tag['level'] == 'E':
            test_case.add_error_info(tag.get('description'), tag['output'])
        else:
            test_case.add_skipped_info(tag.get('description'), tag['output'])
        test_cases.append(test_case)

    return test_cases


def main():
    """ Convert the lintian output into a junit xml file
    """
    argparser = argparse.ArgumentParser(
        description='''Convert lintian output's into a junit xml file''')
    argparser.add_argument('input', type=open, help='Input file',
                           nargs='?', default=sys.stdin)
    argparser.add_argument('-o', '--output', type=argparse.FileType('w'),
                           help='Output file', default=sys.stdout)
    args = argparser.parse_args()

    tags = read_lintian_output(args.input)
    print(tags)

    test_cases = generate_test_cases(tags)
    print(test_cases)

    test_suite = TestSuite('Lintian', test_cases)
    args.output.write(TestSuite.to_xml_string([test_suite]))

if __name__ == "__main__":
    main()
